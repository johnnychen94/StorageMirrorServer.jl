# Modified from PkgServer.jl
# https://github.com/JuliaPackaging/PkgServer.jl/blob/ff2ed7bf179689b3b985ad268b986e53801aaea5/src/PkgServer.jl

const REGISTRIES = Dict(
    "23338594-aafe-5451-b93e-139f81909106" =>
        "https://github.com/JuliaRegistries/General",
)

const uuid_re = raw"[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}(?-i)"
const hash_re = raw"[0-9a-f]{40}"
const meta_re     = Regex("^/meta\$")
const registry_re = Regex("^/registry/($uuid_re)/($hash_re)\$")
const resource_re = Regex("""
    ^/registries\$
  | ^/registry/$uuid_re/$hash_re\$
  | ^/package/$uuid_re/$hash_re\$
  | ^/artifact/$hash_re\$
""", "x")
const hash_part_re = Regex("/($hash_re)\$")

function get_registries(server::String)
    regs = Dict{String,String}()
    response = HTTP.get("$server/registries")
    for line in eachline(IOBuffer(response.body))
        m = match(registry_re, line)
        if m !== nothing
            uuid, hash = m.captures
            uuid in keys(REGISTRIES) || continue
            regs[uuid] = hash
        else
            @error "invalid response" server=server resource="/registries" line=line
        end
    end
    return regs
end

# priority: upstream::AbstractString > JULIA_PKG_SERVER > nothing
function get_upstream(upstream::AbstractString)
    startswith(upstream, r"\w+://") || (upstream = "https://$upstream")
    return String(rstrip(upstream, '/'))
end
function get_upstream(upstream::Nothing=nothing)
    upstream = get(ENV, "JULIA_PKG_SERVER", nothing)
    return isnothing(upstream) ? nothing : get_upstream(upstream)
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
        end
    catch e
        rm(temp_file; force=true)
        rethrow(e)
    end
end

function tarball_git_hash(tarball::String)
    local tree_hash
    mktempdir() do tmp_dir
        run(`tar -C $tmp_dir -zxf $tarball`)
        tree_hash = bytes2hex(Pkg.GitTools.tree_hash(tmp_dir))
        chmod(tmp_dir, 0o777, recursive=true)
    end
    return tree_hash
end

download_and_verify(::Nothing, resource, path) = false
function download_and_verify(server::String, resource::String, path::String)
    hash = let m = match(hash_part_re, resource)
        m !== nothing ? m.captures[1] : nothing
    end

    if isnothing(hash)
        @warn "bad resource: valid hash not found" server=server resource=resource
        return false
    end

    # Instead of verifying hash, which requires a lot of IO reads, a faster way is to
    # make sure the file isn't created if download/creation of tarball fails
    isfile(path) && return true

    write_atomic(path) do temp_file, io
        response = HTTP.get(
            status_exception = false,
            response_stream = io,
            server * resource,
        )
        # Raise warnings about bad HTTP response codes
        if response.status != 200
            @warn "response status $(response.status)" server=server resource=resource
            return false
        end

        # If we're given a hash, then check tarball git hash
        if hash !== nothing
            tree_hash = tarball_git_hash(temp_file)
            # Raise warnings about resource hash mismatches
            if hash != tree_hash
                @warn "resource hash mismatch" server=server resource=resource hash=tree_hash
                return false
            end
        end

        return true
    end

    return isfile(path)
end
