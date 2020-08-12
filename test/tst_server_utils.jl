using StorageMirrorServer: get_hash, RegistryMeta, query_latest_hash, url_exists
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
    "https://pkg.julialang.org",
    "https://us-east.pkg.julialang.org",
    "https://us-east.storage.juliahub.com",
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
    mock(HTTP.request => Mock(http_status_error_mock(200))) do _request
        @test url_exists("https://pkg.julialang.org/registries")
    end
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

            err_msg = @capture_err query_latest_hash(registry, upstreams[1])
            @test occursin("failed to fetch resource", err_msg)
            @test occursin("TimeoutException(15.0)", err_msg)
        end

        mock(HTTP.get => Mock((a...; kw...) -> throw(http_status_error_mock(404)))) do _get
            @test nothing === @suppress_err query_latest_hash(registry, upstreams[1]; timeout=0)

            err_msg = @capture_err treehash = query_latest_hash(registry, upstreams[1]; timeout=0)
            @test occursin("failed to fetch resource", err_msg)
            @test occursin("404 Not Found", err_msg)
        end
    end

    @testset "multiple upstreams" begin
        @test !isnothing(match(r"[0-9a-f]{40}", query_latest_hash(registry, upstreams)))

        mock((query_latest_hash, RegistryMeta, AbstractString) => Mock(nothing)) do _query
            @test nothing === @suppress_err query_latest_hash(registry, upstreams)
            err_msg = @capture_err query_latest_hash(registry, upstreams)
            @test occursin("failed to find available registry", err_msg)
        end
    end
end
