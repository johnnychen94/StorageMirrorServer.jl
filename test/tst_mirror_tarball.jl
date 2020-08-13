using StorageMirrorServer: RegistryMeta, query_latest_hash, download_and_verify, query_artifacts
using StorageMirrorServer: decompress
using StorageMirrorServer: timeout_call

@testset "mirror_tarball" begin
    tmp_testdir = mktempdir()

    registry = RegistryMeta("General", "23338594-aafe-5451-b93e-139f81909106", "https://github.com/JuliaRegistries/General")
    server = "https://us-east.storage.juliahub.com"
    registry_hash = query_latest_hash(registry, server)

    tarball = joinpath(tmp_testdir, "registry", registry.uuid, registry_hash)
    resource = "/registry/$(registry.uuid)/$(registry_hash)"
    download_and_verify(server, resource, tarball)
    @test isfile(tarball)

    packages = mktempdir() do tmpdir
        open(tarball, "r") do io
            Tar.extract(decompress(io), tmpdir)
        end
        # only returns packages that are not stored in static_dir
        read_packages(tmpdir; fetch_full_registry=false, static_dir=tmp_testdir, latest_versions_num=1) do pkg
            occursin("MbedTLS", pkg.name)
        end
    end

    rst_hash = timeout_call(1200) do
        mirror_tarball(registry, [server], tmp_testdir; packages=packages)
    end
    @test rst_hash == registry_hash

    # test if all packages are downloaded
    for pkg in packages
        for (ver, hash_info) in pkg.versions
            tree_hash = hash_info["git-tree-sha1"]
            tarball = joinpath(tmp_testdir, "package", pkg.uuid, tree_hash)
            @test isfile(tarball)
        end
    end

    # test if all artifacts are downloaded
    artifacts = query_artifacts(tmp_testdir; fetch_full=false)
    @test isempty(artifacts)

    registries_file = joinpath(tmp_testdir, "registries")
    @test isfile(registries_file) && occursin(resource, readline(registries_file))
end
