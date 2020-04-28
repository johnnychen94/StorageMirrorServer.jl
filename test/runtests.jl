using StorageServer
using Test
using ReferenceTests

@testset "StorageServer.jl" begin
    include("tst_artifact.jl")
    include("tst_package.jl")
    include("tst_registry.jl")
end
