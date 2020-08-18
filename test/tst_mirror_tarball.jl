using StorageMirrorServer: RegistryMeta, query_latest_hash, download_and_verify, query_artifacts, read_packages, read_records
using StorageMirrorServer: mirror_tarball
using StorageMirrorServer: decompress
using StorageMirrorServer: timeout_call
using Tar

@testset "mirror_tarball" begin
    tmp_testdir = mktempdir()
    # tmp_testdir = abspath("..", "julia")
    # rm(tmp_testdir; force=true, recursive=true)

    registry = RegistryMeta("General", "23338594-aafe-5451-b93e-139f81909106", "https://github.com/JuliaRegistries/General")
    upstreams = ["https://mirrors.bfsu.edu.cn/julia", "https://mirrors.sjtug.sjtu.edu.cn/julia", "https://us-east.storage.juliahub.com", "https://kr.storage.juliahub.com"]
    registry_hash = query_latest_hash(registry, upstreams)

    tarball = joinpath(tmp_testdir, "registry", registry.uuid, registry_hash)
    resource = "/registry/$(registry.uuid)/$(registry_hash)"
    download_and_verify(upstreams, resource, tarball)
    @test isfile(tarball)

    packages = mktempdir() do tmpdir
        rst = []
        open(tarball, "r") do io
            Tar.extract(decompress(io), tmpdir)
        end
        # only returns packages that are not stored in static_dir
        append!(rst, read_packages(tmpdir; fetch_full_registry=false, static_dir=tmp_testdir, latest_versions_num=1) do pkg
            occursin("MbedTLS", pkg.name) # platform-dependent artifacts
        end)
        append!(rst, read_packages(tmpdir; fetch_full_registry=false, static_dir=tmp_testdir, latest_versions_num=1, recursive=false) do pkg
            occursin("TestImages", pkg.name) || # platform-independent artifacts
            occursin("StanMCMCChain", pkg.name) # vanished resources
        end)
        return rst
    end

    @time rst_hash = timeout_call(2400) do
        mirror_tarball(registry, upstreams, tmp_testdir; packages=packages, registry_hash=registry_hash)
    end
    @test rst_hash == registry_hash

    # test if all packages are downloaded
    for pkg in packages
        for (ver, hash_info) in pkg.versions
            tree_hash = hash_info["git-tree-sha1"]
            tarball = joinpath(tmp_testdir, "package", pkg.uuid, tree_hash)
            if pkg.name == "StanMCMCChain"
                # instead this one should be listed in "/failed_resources.txt"
                @test !isfile(tarball)
            else
                @test isfile(tarball)
            end
        end
    end

    # test if all artifacts are downloaded
    artifacts = query_artifacts(tmp_testdir; fetch_full=false)
    @test isempty(artifacts)

    registries_file = joinpath(tmp_testdir, "registries")
    @test isfile(registries_file) && occursin(resource, readline(registries_file))

    # test if vanished resources are listed here
    failed_resources_log = joinpath(tmp_testdir, "failed_resources.txt")
    @test isfile(failed_resources_log)
    open(failed_resources_log, "a") do io
        println(io, "/artifact/uuid/arti") # invalid line
    end
    failed_records = read_records(failed_resources_log)
    for pkg_uuid in [
        "8f1571ae-b3a1-52af-8ab1-32258739efdb", # StanMCMCChain
    ]
        @test any(x->occursin(pkg_uuid, x), failed_records)
    end
    @test all(x->!occursin("/artifact/uuid/arti", x), failed_records)

    # an immediately incremental build should does nothing
    tarball = joinpath(tmp_testdir, "registry", registry.uuid, registry_hash)
    packages = mktempdir() do tmpdir
        rst = []
        open(tarball, "r") do io
            Tar.extract(decompress(io), tmpdir)
        end
        # only returns packages that are not stored in static_dir
        append!(rst, read_packages(tmpdir; fetch_full_registry=false, static_dir=tmp_testdir, latest_versions_num=1) do pkg
            occursin("MbedTLS", pkg.name) # platform-dependent artifacts
        end)
        append!(rst, read_packages(tmpdir; fetch_full_registry=false, static_dir=tmp_testdir, latest_versions_num=1, recursive=false) do pkg
            occursin("TestImages", pkg.name) || # platform-independent artifacts
            occursin("StanMCMCChain", pkg.name) # vanished resources
        end)
        return rst
    end
    @time err_msg = timeout_call(60) do
        @capture_err mirror_tarball(registry, upstreams, tmp_testdir; packages=packages, registry_hash=registry_hash)
    end
    @test occursin("$(length(packages)) previously failed resources are skipped during this build", err_msg)
end
