mktempdir() do tmp_root

registry_root = joinpath(tmp_root, "registries", "Test")
run(`git clone https://github.com/johnnychen94/Test $registry_root`)

@testset "read_packages" begin
    test_full = read_packages(registry_root)
    @test length(test_full) == 5

    test_one_version = read_packages(registry_root, latest_versions_num=1)
    @test length(test_one_version) == 5
    @test length(first(test_one_version).versions) == 1

    test_selected_package = read_packages(registry_root) do pkg
        occursin("FFTW", pkg.url)
    end
    @test length(test_selected_package) == 3
end

@testset "make_tarball" begin
    mktempdir() do download_root
        static_dir = joinpath(download_root, "static")
        cd(download_root) do
            make_tarball(registry_root; static_dir=static_dir, show_progress=false)

            @test isfile(joinpath(static_dir, "registries"))
            registry_dir = joinpath(static_dir, "registry")
            @test isdir(registry_dir)
            isdir(registry_dir) && @test length(readdir(registry_dir)) == 1

            pkg_dir = joinpath(static_dir, "package")
            @test isdir(pkg_dir)
            isdir(pkg_dir) && @test length(readdir(pkg_dir)) == 5

            artifact_dir = joinpath(static_dir, "artifact")
            @test isdir(artifact_dir)
            isdir(artifact_dir) && @test length(readdir(artifact_dir)) == 13
        end
    end
end
end
