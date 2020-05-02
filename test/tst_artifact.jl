using StorageServer: Artifact, verify_tarball_hash
using Pkg: TOML
using Base: SHA1

# libpng_jll.jl
let
mktempdir() do static_dir
    artifact = """
    [[libpng]]
    arch = "i686"
    git-tree-sha1 = "f25c3958c4f91f33d35edd27a022bf6b98c97f56"
    libc = "musl"
    os = "linux"

        [[libpng.download]]
        sha256 = "913a78d54f70409dc664f98d0bba5585f542b366491a31f069d0a84d00ad5a99"
        url = "https://github.com/JuliaBinaryWrappers/libpng_jll.jl/releases/download/libpng-v1.6.37+3/libpng.v1.6.37.i686-linux-musl.tar.gz"
    """

    artifact = Artifact(TOML.parse(artifact)["libpng"][1])

    sha1_str = "f25c3958c4f91f33d35edd27a022bf6b98c97f56"
    @test artifact.hash == SHA1(sha1_str)
    @test artifact.tarball == "artifact/$sha1_str"
    @test length(artifact.downloads) == 1
    @test artifact.downloads[1] == Dict(
        "sha256"=>"913a78d54f70409dc664f98d0bba5585f542b366491a31f069d0a84d00ad5a99",
        "url"=>"https://github.com/JuliaBinaryWrappers/libpng_jll.jl/releases/download/libpng-v1.6.37+3/libpng.v1.6.37.i686-linux-musl.tar.gz")

    cd(static_dir) do
        @test isempty(readdir(static_dir))
        make_tarball(artifact; static_dir=static_dir)
        @test readdir("artifact") == [sha1_str]
        @test true == verify_tarball_hash(artifact.tarball, artifact.hash)
    end
end
end

# TestImages.jl
let
mktempdir() do static_dir
    artifact = """
    [[FFTW]]
    arch = "aarch64"
    git-tree-sha1 = "cf77334a792d1bbf348c1a2934309828f6cb9742"
    libc = "musl"
    os = "linux"

        [[FFTW.download]]
        sha256 = "6d1741b3183b1dcb9099ac50653a2bb126fee96d7ae7e3cb73d511cfff122cfd"
        url = "https://github.com/JuliaBinaryWrappers/FFTW_jll.jl/releases/download/FFTW-v3.3.9+5/FFTW.v3.3.9.aarch64-linux-musl.tar.gz"
    """

    artifact = Artifact(TOML.parse(artifact)["FFTW"][1])

    sha1_str = "cf77334a792d1bbf348c1a2934309828f6cb9742"
    @test artifact.hash == SHA1(sha1_str)
    @test artifact.tarball == "artifact/$sha1_str"
    @test length(artifact.downloads) == 1

    cd(static_dir) do
        @test isempty(readdir(static_dir))
        make_tarball(artifact; static_dir=static_dir)
        @test readdir(joinpath(static_dir, "artifact")) == [sha1_str]
        @test true == verify_tarball_hash(artifact.tarball, artifact.hash)
    end
end
end

let
not_existed = SHA1("180efde45f515a31b6a54cdba84088f4aaad63a1")
x = Artifact(not_existed, "tmp", [])
output = @capture_err begin
    make_tarball(x; download_only=true)
end
@test occursin("failed to fetch artifact: $not_existed", output)
end
