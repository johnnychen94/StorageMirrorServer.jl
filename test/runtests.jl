using StorageMirrorServer
using HTTP

using Tar
using Test
using Dates
using Random
using Suppressor
using SimpleMock

if VERSION < v"1.4"
    error("These tests require Julia at least v1.4")
end

include("test_utils.jl")

@testset "StorageServer" begin
    include("tst_utils.jl")
    include("tst_server_utils.jl")
    include("tst_mirror_tarball.jl")
end
