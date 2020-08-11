using StorageMirrorServer
using Test
using Dates
using Suppressor

if VERSION < v"1.4"
    error("These tests require Julia at least v1.4")
end

@testset "StorageServer" begin
    include("tst_utils.jl")
end
