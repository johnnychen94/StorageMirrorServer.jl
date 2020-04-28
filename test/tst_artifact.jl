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
    ["autumn_leaves.png"]
    git-tree-sha1 = "cb84c2e2544f3517847d90c13cc11ab911fdbc5c"
    """

    artifact = Artifact(TOML.parse(artifact)["autumn_leaves.png"])

    sha1_str = "cb84c2e2544f3517847d90c13cc11ab911fdbc5c"
    @test artifact.hash == SHA1(sha1_str)
    @test artifact.tarball == "artifact/$sha1_str"
    @test length(artifact.downloads) == 0

    cd(static_dir) do
        @test isempty(readdir(static_dir))
        make_tarball(artifact; static_dir=static_dir)
        @test readdir(joinpath(static_dir, "artifact")) == [sha1_str]
        @test true == verify_tarball_hash(artifact.tarball, artifact.hash)
    end
end
end
