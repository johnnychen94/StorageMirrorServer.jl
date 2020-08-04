using StorageMirrorServer
using Test
using Suppressor

if VERSION < v"1.4"
    error("These tests require Julia at least v1.4")
end

# tmp_root = mktempdir()
# Base.Filesystem.temp_cleanup_later(tmp_root)
# tmp_registry_root = joinpath(tmp_root, "registries", "Test")
# run(`git clone https://github.com/johnnychen94/Test $tmp_registry_root`)

# tmp_depot = mktempdir()
# Base.Filesystem.temp_cleanup_later(tmp_depot)
# pushfirst!(DEPOT_PATH, tmp_root)

# @testset "StorageServer.jl" begin
#     include("tst_artifact.jl")
#     include("tst_package.jl")
#     include("tst_registry.jl")
# end
