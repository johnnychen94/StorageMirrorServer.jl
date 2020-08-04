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
