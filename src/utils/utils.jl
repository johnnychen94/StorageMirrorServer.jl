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
    with_cache_dir(f, cache_dir; by=isdir) -> Bool

Conditionally run function `f()` based on the status of `by(cache_dir)`.

If `by(cache_dir) == false`, then `f()` get called. By default, `by = isdir` and thus doesn't verify
the contents of `cache_dir`.

`cache_dir` will be cleaned up if either of the case happens:

* an exception is thrown,
* `f() == false`
* `by(cache_dir) == false` 


!!! note
    The return value indicates only whether the `cache_dir` is kept. A `true` return valuet doesn't
    necessarily indicate that `f()` gets called successfully; `f()` might never get called.


# Examples

```jldoctest
julia> cache_dir = tempname();

julia> logfile = joinpath(cache_dir, "log.txt");

julia> function f(logfile)
           mkpath(dirname(logfile))
           open(logfile, "w") do io
               print(io, now())
           end
       end
f (generic function with 1 method)

julia> with_cache_dir(cache_dir) do
    f(logfile)
    @info "This gets called"
end
[ Info: This gets called
true

julia> with_cache_dir(cache_dir) do
    f(logfile)
    @info "This doesn't get called"
end
true
```

"""
function with_cache_dir(f, cache_dir::AbstractString; by=isdir)
    # by(cache_dir) might error if `cache_dir` doesn't exist
    verify() = isdir(cache_dir) && by(cache_dir)
    clean_up() = rm(cache_dir; force=true, recursive=true)

    verify() && return true
    try
        rst = f()
        if rst === false || !verify()
            clean_up()
            return false
        else
            return true
        end
    catch err
        clean_up()
        rethrow(err)
    end
end
