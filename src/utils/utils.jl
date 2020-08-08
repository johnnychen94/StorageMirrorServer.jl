struct TimeoutException <: Exception end

"""
    timeout_call(f, timeout; pollint=0.1)

Execute function `f()` with a maximum timeout `timeout`.
"""
function timeout_call(f::Function, timeout::Real; pollint=0.1)
    start = now()

    t = @task f()
    schedule(t)

    while !istaskdone(t)
        if (now()-start).value >= 1000timeout
            schedule(t, TimeoutException(), error=true)
            break
        end
        sleep(pollint)
    end

    return t.result
end

"""
    with_cache_dir(f, cache_dir)

If `cache_dir` already exists, then skip running `f()`.

`f` should return `true` to indicate a success status. In any other cases, `cache_dir` will be 
cleaned up.
"""
function with_cache_dir(f, cache_dir::AbstractString)
    isdir(cache_dir) && return true
    clean_up() = rm(cache_dir; force=true, recursive=true)
    try
        f() === true || clean_up()
    catch err
        clean_up()
        rethrow(err)
    end
end
