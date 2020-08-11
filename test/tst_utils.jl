using StorageMirrorServer: timeout_call, TimeoutException

@testset "timeout_call" begin
    timeout_err = TimeoutException(1)
    msg = @capture_err try
        throw(timeout_err)
    catch err
        @warn err
    end
    @test occursin(string(timeout_err), msg)

    try
        response = timeout_call(2) do 
            sleep(1)
            return true
        end
        @test response == true
    catch err
        @test false # should never reach here
    end

    try
        response = timeout_call(1) do
            sleep(2)
            return true
        end
        @test false # should never reach here
    catch err
        @test err isa TimeoutException && err.timeout == 1
    end

    try
        response = timeout_call(2) do
            sleep(1)
            error("reached here")
        end
        @test false # should never reach here
    catch err
        @test err isa ErrorException && err.msg == "reached here"
    end

    try
        response = timeout_call(1) do
            sleep(2)
            @test false # should never reach here
        end
        @test false # should never reach here
    catch err
        @test err isa TimeoutException && err.timeout == 1
    end

    start_time = now()
    Threads.@threads for i in 1:8
        try
            response = timeout_call(5) do
                sleep(1)
                return true
            end
            response == true || error("should never reach here")
        catch err
            error("should never reach here")
        end
    end
    # each iteration should end in about 1 - 1.5s
    @test 8_000 < (now() - start_time).value * Threads.nthreads() < 1.5 * 8_000

    start_time = now()
    Threads.@threads for i in 1:8
        try
            response = timeout_call(1) do
                sleep(5)
                error("should never reach here")
            end
            error("should never reach here")
        catch err
            if !(err isa TimeoutException && err.timeout == 1)
                rethrow(err)
            end
        end
    end
    # each iteration should end in about 1 - 1.5s
    @test 8_000 < (now() - start_time).value * Threads.nthreads() < 1.5 * 8_000
end



