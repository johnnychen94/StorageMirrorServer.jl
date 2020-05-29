# Modified from PkgServer.jl
# https://github.com/JuliaPackaging/PkgServer.jl/blob/ff2ed7bf179689b3b985ad268b986e53801aaea5/src/PkgServer.jl

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

download_and_verify(::Nothing, resource, path) = false
function download_and_verify(server::String, resource::String, path::String)
    hash = let m = match(Regex("/([0-9a-f]{40})\$"), resource)
        m !== nothing ? m.captures[1] : nothing
    end

    if isnothing(hash)
        @warn "bad resource: valid hash not found" server=server resource=resource
        return false
    end

    # Verifying hash requires a lot of IO reads. A faster way is to only check if the file
    # exists. This is okay if we can make sure the file isn't created when download/creation
    # of tarball fails
    isfile(path) && return true

    write_atomic(path) do temp_file, io
        response = HTTP.get(
            status_exception = false,
            response_stream = io,
            server * resource,
        )
        # Raise warnings about bad HTTP response codes
        if response.status != 200
            @debug "response status $(response.status)" server=server resource=resource
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
