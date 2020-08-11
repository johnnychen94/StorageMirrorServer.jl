struct TimeoutException <: Exception
    timeout::Float64 # seconds
end

"""
    timeout_call(f, timeout; pollint=0.1)

Execute function `f()` with a maximum timeout `timeout` seconds.

An `TimeoutException(timeout)` exception will be thrown if it exceeds
the maximum timeout. If `f()` exits with error, it will be rethrown.
"""
function timeout_call(f::Function, timeout::Real; pollint=0.1)
    start = now()

    t = @task f()
    schedule(t)

    while !istaskdone(t)
        if (now()-start).value >= 1000timeout
            schedule(t, TimeoutException(timeout), error=true)
            sleep(pollint) # wait a while for the task to update its state
            break
        end
        sleep(pollint)
    end

    if t.state == :failed
        throw(t.exception)
    else
        return t.result
    end
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
