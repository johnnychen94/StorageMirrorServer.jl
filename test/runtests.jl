using StorageServer
using Test
using Suppressor

@testset "StorageServer.jl" begin
    include("tst_artifact.jl")
    include("tst_package.jl")
    include("tst_registry.jl")
end
