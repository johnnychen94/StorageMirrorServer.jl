using StorageMirrorServer: timeout_call, TimeoutException, with_cache_dir

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

@testset "with_cache_dir" begin
    @testset "case 1" begin
        # case 1: the first function call succeeds

        cache_dir = tempname()
        logfile = joinpath(cache_dir, "log.txt")

        @test !isdir(cache_dir) && !isfile(logfile)
        with_cache_dir(cache_dir) do
            mkpath(cache_dir)
            open(logfile, "w") do io
                print(io, "This should be called.")
            end
        end
        @test isdir(cache_dir) && isfile(logfile)
        isfile(logfile) && @test read(logfile, String) == "This should be called."

        with_cache_dir(cache_dir) do
            open(logfile, "w") do io
                print(io, "This doesn't get called")
            end
            @test false # mark a fail case if this get called
        end
        @test isfile(logfile)
        isfile(logfile) && @test read(logfile, String) == "This should be called."
    end

    @testset "case 2" begin
        # case 2: the first function get called but returns a false

        cache_dir = tempname()
        logfile = joinpath(cache_dir, "log.txt")

        @test !isdir(cache_dir) && !isfile(logfile)
        with_cache_dir(cache_dir) do
            mkpath(cache_dir)
            open(logfile, "w") do io
                print(io, "This get called.")
            end
            return false
        end
        @test !isdir(cache_dir) && !isfile(logfile)

        with_cache_dir(cache_dir) do
            mkpath(cache_dir)
            open(logfile, "w") do io
                print(io, "This get called again.")
            end
        end
        @test isfile(logfile)
        isfile(logfile) && @test read(logfile, String) == "This get called again."
    end

    @testset "case 3" begin
        # case 3: the first get called but an exception is thrown

        cache_dir = tempname()
        logfile = joinpath(cache_dir, "log.txt")

        @test !isdir(cache_dir) && !isfile(logfile)
        try
            with_cache_dir(cache_dir) do
                mkpath(cache_dir)
                open(logfile, "w") do io
                    print(io, "This get called.")
                end
                error("some error")
            end
        catch err
            @test err isa ErrorException && err.msg == "some error"
        end
        @test !isdir(cache_dir) && !isfile(logfile)

        with_cache_dir(cache_dir) do
            mkpath(cache_dir)
            open(logfile, "w") do io
                print(io, "This get called again.")
            end
        end
        @test isfile(logfile)
        isfile(logfile) && @test read(logfile, String) == "This get called again."
    end

    @testset "case 4" begin
        # case 4: cache isn't valid anymore
        cache_dir = tempname()
        logfile = joinpath(cache_dir, "log.txt")

        is_valid_cache(cache_dir) = "log.txt" in readdir(cache_dir)

        @test !isdir(cache_dir)
        with_cache_dir(cache_dir; by=is_valid_cache) do
            mkpath(cache_dir)
            @test !is_valid_cache(cache_dir)
        end
        @test !isdir(cache_dir)

        with_cache_dir(cache_dir; by=is_valid_cache) do
            mkpath(cache_dir)
            open(logfile, "w") do io
                print(io, "This get called.")
            end
        end
        @test isfile(logfile)
        isfile(logfile) && @test read(logfile, String) == "This get called."
    end

end
