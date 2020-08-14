using StorageMirrorServer: get_hash, RegistryMeta, query_latest_hash, url_exists
using StorageMirrorServer: download_and_verify
using StorageMirrorServer: timeout_call, TimeoutException

@testset "normalize_upstream" begin
    upstreams = [
        "https://pkg.julialang.org",
        "https://pkg.julialang.org/",
        "pkg.julialang.org",
        "pkg.julialang.org/",
    ]
    for server in upstreams
        @test "https://pkg.julialang.org" == StorageMirrorServer.normalize_upstream(server)
    end
end

registry = RegistryMeta(
    "General",
    "23338594-aafe-5451-b93e-139f81909106",
    "https://github.com/JuliaRegistries/General"
)

upstreams = [
    "https://mirrors.sjtug.sjtu.edu.cn/julia",
    "https://mirrors.bfsu.edu.cn/julia"
    # "https://pkg.julialang.org",
    # "https://us-east.storage.juliahub.com",
]

@testset "get_hash" begin
    treehash = "e1e1667fcb629f2c9ec4ac43464c2ef6177ed696"
    @test treehash == get_hash("/registry/23338594-aafe-5451-b93e-139f81909106/$treehash\n", registry.uuid)
    @test treehash == get_hash(IOBuffer("/registry/23338594-aafe-5451-b93e-139f81909106/$treehash\n"), registry.uuid)

    # uuid not found
    @test nothing === get_hash("/registry/00000000-1111-2222-3333-444444444444/$treehash\n", registry.uuid)
    # invalid lines
    @test nothing === get_hash("hello world", registry.uuid)
    # whitespaces are ignored
    @test treehash == get_hash("hello world\n /registry/23338594-aafe-5451-b93e-139f81909106/$treehash \n", registry.uuid)
end

@testset "url_exists" begin
    # @test url_exists("https://pkg.julialang.org/registries"; timeout=0)
    @test !url_exists("https://pkg.julialang.org/registries_1234")
    mock(timeout_call => Mock((f, x) -> throw(TimeoutException(0.001)))) do _timeout_call
        @test @suppress_err !url_exists("https://pkg.julialang.org/registries"; timeout=1)
    end

    @test_throws ArgumentError url_exists("abc")
    err_msg = @capture_err url_exists("https://abc")
    @test occursin("failed to send HEAD request", err_msg)
end

@testset "query_latest_hash" begin
    @testset "single upstream" begin
        @test !isnothing(match(r"[0-9a-f]{40}", query_latest_hash(registry, upstreams[1])))

        mock(timeout_call => Mock((f, x) -> throw(TimeoutException(15)))) do _timeout_call
            @test nothing === @suppress_err query_latest_hash(registry, upstreams[1])

            # url_exists is mocked, too
            err_msg = @capture_err query_latest_hash(registry, upstreams[1])
            @test occursin("failed to fetch resource", err_msg) || occursin("failed to send HEAD request", err_msg)
            @test occursin("TimeoutException(15.0)", err_msg)
        end
    end
end

@testset "download_and_verify" begin
    tmp_testdir = mktempdir()

    resource_list = [
        "/artifact/ff8ad169326afd41d46f507a960c1717f4ed1a47",
        "/artifact/f8eb2f3aa430c1ea80c46779ba89580372f0f0db",
        "/package/a603d957-0e48-4f86-8fbd-0b7bc66df689/e4581e3fadda3824e0df04396c85258a2107035d",
        "/package/22bb73d7-edb2-5785-ba1e-7d60d6824784/41731998eb760f9c5e4acc911c9fb33c9643365f",
    ]
    for resource in resource_list
        tarball = joinpath(tmp_testdir, resource[2:end])
        @test download_and_verify(upstreams, resource, tarball)
        @test isfile(tarball)
    end

    server = "https://mirrors.bfsu.edu.cn/julia"
    # invalid hash
    resource = "/artifact/0000"
    tarball = joinpath(tmp_testdir, resource[2:end])
    @test @suppress_err !download_and_verify(server, resource, tarball)
    err_msg = @capture_err download_and_verify(server, resource, tarball)
    @test occursin("bad resource: valid hash not found", err_msg)

    # 404 test
    resource = "/artifact/0000000000000000000000000000000000000000"
    tarball = joinpath(tmp_testdir, resource[2:end])
    @test @suppress_err !download_and_verify(server, resource, tarball)
    err_msg = @capture_err download_and_verify(server, resource, tarball)
    @test occursin("failed to fetch resource", err_msg)

    # timeout test
    # server = "https://us-east.storage.juliahub.com"
    # resource = resource_list[1]
    # tarball = joinpath(tmp_testdir, resource[2:end])
    # config = Dict{Symbol, Any}(:timeout => 0.001)
    # @test @suppress_err !download_and_verify(server, resource, tarball; http_parameters=config)
    # err_msg = @capture_err download_and_verify(server, resource, tarball; http_parameters=config)
    # @test occursin("failed to fetch resource", err_msg)
    # @test occursin("TimeoutException(0.001)", err_msg)
    # @test !isfile(tarball)

    # TODO: test hash mismatch
end
