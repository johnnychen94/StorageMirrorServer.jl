using Pkg: TOML
using StorageServer: Package
using StorageServer: get_registry_path
using FFTW_jll

let
# FFTW_jll
static_dir = "static"
clones_dir = "clones"

uuid = "f5851436-0d7a-5f13-b9de-f02708fd171a"
registry_item_dir = joinpath(tmp_registry_root, "F", "FFTW_jll")
pkg = Package("FFTW_jll", uuid, registry_item_dir)


versions_toml = TOML.parsefile(joinpath(registry_item_dir, "Versions.toml"))
versions_sha = Set([item["git-tree-sha1"] for item in values(versions_toml)])

artifacts_toml = TOML.parsefile(joinpath(pkgdir(FFTW_jll), "Artifacts.toml"))
artifacts_sha = Set([item["git-tree-sha1"] for item in values(artifacts_toml["FFTW"])])

mktempdir() do root_dir
    cd(root_dir) do
        make_tarball(pkg; static_dir=static_dir, clones_dir=clones_dir)

        # test if source codes of all versions are archived
        source_dir = joinpath(root_dir, static_dir, "package", uuid)
        @test isdir(source_dir)
        isdir(source_dir) && @test Set(readdir(source_dir)) == versions_sha

        # test if all artifacts are archived
        artifacts_dir = joinpath(root_dir, static_dir, "artifact")
        @test Set(readdir(artifacts_dir)) == artifacts_sha
    end
end
end

let
# https://github.com/rjdverbeek-tud/Atmosphere.jl.git doesn't exists

static_dir = "static"
clones_dir = "clones"

uuid = "2c84d669-3b95-46c3-a358-9a76f739ac9c"
registry_item_dir = joinpath(get_registry_path("General"), "A", "Atmosphere")

pkg = Package("Atmosphere.jl", uuid, registry_item_dir)

mktempdir() do root_dir
    cd(root_dir) do
        output = @capture_err begin
            make_tarball(pkg; static_dir=static_dir, clones_dir=clones_dir)
        end
        @test occursin("failed to request $(pkg.url)", output)

        # failed to clone
        source_dir = joinpath(root_dir, static_dir, "package", uuid)
        @test !isdir(source_dir)
    end
end
end
