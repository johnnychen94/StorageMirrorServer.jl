# Most of the codes here are copied and modified from PkgServer.jl

const uuid_re = raw"[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}(?-i)"
const hash_re = raw"[0-9a-f]{40}"
const registry_re = Regex("^/registry/($uuid_re)/($hash_re)\$")
const resource_re = Regex("""
    ^/registry/$uuid_re/($hash_re)\$
  | ^/package/$uuid_re/($hash_re)\$
  | ^/artifact/($hash_re)\$
""", "x")

"""
    query_latest_hash(registry, server)

Interrogate a storage server for a list of registries, match the response against the
registries we are paying attention to, and return the matching hash.

If registry is not avilable in server, then return `nothing`.
"""
function query_latest_hash(registry::RegistryMeta, server::AbstractString)
    response = nothing
    try
        response = timeout_call(15) do
            HTTP.get("$server/registries", retry=false)
        end
    catch err
        err isa TimeoutException && return nothing
        rethrow(err)
    end
    # FIXME: this is only a temporary workaround, I'm not very sure how response can be a DNSError after
    # the try-catch blcok
    response isa Exception && return nothing
    isnothing(response) && return nothing

    get_hash(IOBuffer(response.body), registry.uuid)
end

function get_hash(io, uuid)
    for line in eachline(io)
        m = match(registry_re, line)
        if m !== nothing
            matched_uuid, matched_hash = m.captures
            matched_uuid == uuid && return matched_hash
        end
    end
    return nothing
end

"""
    query_latest_hash(registry::RegistryMeta, upstreams::AbstractVector)

Query `upstreams` and save the latest registry hash to each item of `registries`.
"""
function query_latest_hash(registry::RegistryMeta, upstreams::AbstractVector{<:AbstractString})
    # collect current registry hashes from servers
    uuid = registry.uuid
    hash_info = Dict{String, Vector{String}}() # Dict(hashA => [serverA, serverB], ...)
    servers = String[] # [serverA, serverB]
    for server in upstreams
        hash = query_latest_hash(registry, server)
        isnothing(hash) && continue

        push!(get!(hash_info, hash, String[]), server)
        push!(servers, server)
    end

    # for each hash check what other servers know about it
    if isempty(hash_info)
        # if none of the upstreams contains the registry we want to mirror
        @warn "failed to find available registry" registry=registry.name upstreams=upstreams
        return nothing
    end

    # a hash might be known to many upstreams
    for (hash, hash_servers) in hash_info
        for server in servers
            server in hash_servers && continue
            url_exists("$server/registry/$uuid/$hash") || continue
            push!(hash_servers, server)
        end
    end

    # Ideally, there is an upstream server that knows all hashes, and we set hash in that server
    # as the latest hash. 
    # In practice, we set the first non-malicious hash known to fewest servers as the latest hash.
    hashes = sort!(collect(keys(hash_info)))
    sort!(hashes, by = hash -> length(hash_info[hash]))
    hashes[findfirst(x->verify_registry_hash(registry.source_url, x), hashes)]
end


"""
    normalize_upstream(upstream::AbstractString) -> String

Normalize server url by adding necessary prefix and removing trailing `/`
"""
function normalize_upstream(upstream::AbstractString; prefix = "https")
    startswith(upstream, r"\w+://") || (upstream = "$prefix://$upstream")
    return String(rstrip(upstream, '/'))
end


"""
    url_exists(url)

Send a `HEAD` request to the specified URL, returns `true` if the response is HTTP 200.
"""
function url_exists(url::AbstractString)
    try
        response = timeout_call(5) do
            HTTP.request("HEAD", url, status_exception = false)
        end
        return response.status == 200
    catch err
        err isa TimeoutException && return false
        rethrow(err)
    end
end

"""
    verify_registry_hash(source_url, hash)

Verify that the origin git repository knows about the given registry tree hash.
"""
function verify_registry_hash(source_url::AbstractString, hash::AbstractString)
    url = Pkg.Operations.get_archive_url_for_version(source_url, hash)
    return url === nothing || url_exists(url)
end

"""
    write_atomic(f::Function, path::String)
Performs an atomic filesystem write by writing out to a file on the same
filesystem as the given `path`, then `move()`'ing the file to its eventual
destination.  Requires write access to the file and the containing folder.
Currently stages changes at "<path>.tmp.<randstring>".  If the return value
of `f()` is `false` or an exception is raised, the write will be aborted.
"""
function write_atomic(f::Function, path::String)
    isdir(dirname(path)) || mkpath(dirname(path))
    temp_file = path * ".tmp." * randstring()
    try
        retval = open(temp_file, "w") do io
            f(temp_file, io)
        end
        if retval !== false
            mv(temp_file, path; force=true)
        else
            rm(temp_file; force=true)
        end
    catch e
        rm(temp_file; force=true)
        rethrow(e)
    end
end

function download_and_verify(
        server::String,
        resource::String,
        tarball::String;
        http_parameters::Dict{Symbol, Any} = Dict{Symbol, Any}(),
)
    http_parameters = merge(default_http_parameters, http_parameters)
    http_parameters[:status_exception] = false
    timeout = http_parameters[:timeout]
    delete!(http_parameters, :timeout)

    hash = let m = match(resource_re, resource)
        m !== nothing ? first(filter(x->!isnothing(x), m.captures)) : nothing
    end

    if isnothing(hash)
        @warn "bad resource: valid hash not found" server=server resource=resource tarball=tarball
        return false
    end

    # Verifying hash requires a lot of IO reads. A faster way is to only check if the file
    # exists. This is okay if we can make sure the file isn't created when download/creation
    # of tarball fails
    isfile(tarball) && return true
    url_exists(server * resource) || return false

    write_atomic(tarball) do temp_file, io
        try
            response = timeout_call(timeout) do 
                    HTTP.get(
                        response_stream = io,
                        server * resource;
                        http_parameters...
                    )
            end

            if response.status != 200
                @debug "response status $(response.status)" server=server resource=resource
                return false
            end
        catch err
            if err isa TimeoutException
                @warn "timeout when fetching resource" resource=server * resource
                return false
            end
            rethrow(err)
        end

        # If we're given a hash, then check tarball git hash
        if hash !== nothing
            tree_hash = open(temp_file, "r") do io
                Tar.tree_hash(decompress(io), algorithm="git-sha1")
            end
            
            # Raise warnings about resource hash mismatches
            if hash != tree_hash
                # julia has changed how hash is calculated, which affects empty directory
                # we specially check whethere hash mismatch is caused by this, and if so,
                # skip the warning and make a copy
                ytree_hash = open(temp_file, "r") do io
                    Tar.tree_hash(decompress(io), algorithm="git-sha1", skip_empty=true)
                end

                if hash == ytree_hash
                    yskip_tarball = joinpath(dirname(tarball), ytree_hash)
                    if !isfile(yskip_tarball)
                        temp_yskip_tarball = yskip_tarball * ".tmp." * randstring()
                        cp(temp_file, temp_yskip_tarball)
                        mv(temp_yskip_tarball, yskip_tarball)
                    end
                    return true
                end

                @warn "resource hash mismatch" server=server resource=resource hash=tree_hash
                return false
            end
        end

        return true
    end

    return isfile(tarball)
end


function download_and_verify(
        servers::AbstractVector{String},
        resource::String,
        path::String;
        throw_warnings = true,
        kwargs...
)

    # TODO: async this procedure
    for server in servers
        download_and_verify(server, resource, path; kwargs...) && return true
    end

    throw_warnings && @warn "failed to download resource" servers=join(servers, ", ") resource=resource
    return false
end
