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
    resource = "/registries"

    try
        response = timeout_call(30) do
            HTTP.get(server * resource)
        end
        @debug "succeed to fetch resource" resource=server*resource status=response.status
        return get_hash(IOBuffer(response.body), registry.uuid)
    catch err
        @warn "failed to fetch resource" error=err resource=server*resource
        return nothing
    end
end

get_hash(contents::AbstractString, uuid::AbstractString) = get_hash(IOBuffer(contents), uuid)
function get_hash(io::IO, uuid::AbstractString)
    for line in eachline(io)
        m = match(registry_re, strip(line))
        if m !== nothing
            matched_uuid, matched_hash = m.captures
            matched_uuid == uuid && return matched_hash
        end
    end
    return nothing
end

"""
    query_latest_hash(registry::RegistryMeta, upstreams::AbstractVector)

Query `upstreams` for the latest registry hash. Return `nothing` if given registry isn't available
in all upstreams.
"""
function query_latest_hash(registry::RegistryMeta, upstreams::AbstractVector{<:AbstractString})
    upstreams = normalize_upstream.(upstreams)

    # collect current registry hashes from servers
    uuid = registry.uuid
    hash_info = Dict{String, Vector{String}}() # Dict(hashA => [serverA, serverB], ...)
    servers = String[] # [serverA, serverB]
    @sync for server in upstreams
        @async begin
            hash = query_latest_hash(registry, server)
            if !isnothing(hash)
                push!(get!(hash_info, hash, String[]), server)
                push!(servers, server)
            end
        end
    end

    # for each hash check what other servers know about it
    if isempty(hash_info)
        # reach here if none of the upstreams contains the registry we want to mirror
        @error "failed to find available registry" registry=registry.name uuid=registry.uuid upstreams=join(upstreams, ", ")
        return nothing
    end

    # a hash might be known to many upstreams
    for (hash, hash_servers) in hash_info
        @sync for server in servers
            server in hash_servers && continue
            @async url_exists("$server/registry/$uuid/$hash") && push!(hash_servers, server)
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
    url_exists(url; timeout=30_000)

Send a `HEAD` request to the specified URL, returns `true` if the response is HTTP 200.

Set `timeout=0` millseconds to disable timeout.
"""
function url_exists(url::AbstractString; timeout::Integer=30_000, throw_warnings=true)
    startswith(url, r"https?://") || throw(ArgumentError("invalid url $url, should be HTTP(S) protocol."))

    f() = HTTP.request("HEAD", url, status_exception=false)
    try
        response = timeout==0 ? f() : timeout_call(f, timeout//1000)
        throw_warnings && @debug "succeed to send HEAD request" response=response url=url
        return response.status == 200
    catch err
        throw_warnings && @warn "failed to send HEAD request" error=err url=url
        return false
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
    timeout = http_parameters[:timeout]
    delete!(http_parameters, :timeout)

    hash = let m = match(resource_re, resource)
        m !== nothing ? first(filter(x->!isnothing(x), m.captures)) : nothing
    end

    if isnothing(hash)
        @warn "bad resource: valid hash not found" resource=server*resource tarball=tarball
        return false
    end

    # Verifying hash requires a lot of IO reads. A faster way is to only check if the file
    # exists. This is okay if we can make sure the file isn't created when download/creation
    # of tarball fails
    isfile(tarball) && return true

    write_atomic(tarball) do temp_file, io
        try
            response = timeout_call(timeout) do 
                    HTTP.get(server * resource;
                        response_stream = io,
                        http_parameters...
                    )
            end
        catch err
            @warn "failed to fetch resource" error=err resource=server*resource
            return false
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

                @warn "resource hash mismatch" resource=server*resource reference_hash=hash actual_hash=tree_hash
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
        tarball::String;
        throw_warnings = true,
        kwargs...
)
    isfile(tarball) && return true
    
    race_lock = ReentrantLock()
    task_pool = []

    try
        if length(servers) == 1
            download_and_verify(servers[1], resource, tarball; kwargs...)
        else
            for server in servers
                task = @async begin
                    if url_exists(server*resource; timeout=30_000, throw_warnings=false)
                        # the first that hits here start downloading
                        if trylock(race_lock)
                            retval = download_and_verify(server, resource, tarball; kwargs...)
                            unlock(race_lock)
                            retval
                        end
                    end
                end
                push!(task_pool, task)
            end

            try
                timeout_call(default_http_parameters[:timeout]) do
                    while true
                        sleep(0.1)

                        if any(t->istaskdone(t) && t.result === true, task_pool)
                            interrupt_task(task_pool)
                            return true
                        end

                        if all(istaskdone, task_pool)
                            @warn "fail to download resource" resource=resource tarball=tarball upstreams=join(servers, ", ")
                            return false
                        end
                    end
                end
            catch err
                @warn err
                return false
            end 
        end
    catch e
        throw_warnings && @warn "fail to download resource" err=e resource=resource tarball=tarball upstreams=join(servers, ", ")
        interrupt_task(task_pool)
        return false
    end

    interrupt_task(task_pool)
    if isfile(tarball)
        return true
    else
        throw_warnings && @warn "fail to download resource" resource=resource tarball=tarball upstreams=join(servers, ", ")
        return false
    end
end

function interrupt_task(task_pool)
    isempty(task_pool) && return nothing
    for t in task_pool
        @eval :(Base.throwto(t, InterruptException()))
    end
end
