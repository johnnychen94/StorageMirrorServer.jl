using Pkg: TOML
using StorageServer: Package
using TestImages

let
# TestImages.jl
static_dir = "static"
clones_dir = "clones"

uuid = "5e47fb64-e119-507b-a336-dd2b206d9990"
registry_item_dir = "$(homedir())/.julia/registries/General/T/TestImages"
pkg = Package("TestImages.jl", uuid, registry_item_dir)


versions_toml = TOML.parse(read(joinpath(registry_item_dir, "Versions.toml"), String))
versions_sha = Set([item["git-tree-sha1"] for item in values(versions_toml)])

artifacts_toml = TOML.parse(read(joinpath(pkgdir(TestImages), "Artifacts.toml"), String))
artifacts_sha = Set([item["git-tree-sha1"] for item in values(artifacts_toml)])

mktempdir() do root_dir
    cd(root_dir) do
        make_tarball(pkg; static_dir=static_dir, clones_dir=clones_dir)

        # test if source codes of all versions are archived
        source_dir = joinpath(root_dir, static_dir, "package", uuid)
        @test isdir(source_dir)
        isdir(source_dir) && @test Set(readdir(source_dir)) == versions_sha

        # test if all artifacts of the latest version are archived
        # the latest version is added during CI
        artifacts_dir = joinpath(root_dir, static_dir, "artifact")
        @test Set(readdir(artifacts_dir)) ⊇ artifacts_sha
    end
end
end
