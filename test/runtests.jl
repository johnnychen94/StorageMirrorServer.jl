using StorageMirrorServer
using HTTP

using Tar
using Test
using Dates
using Random
using Suppressor

if VERSION < v"1.4"
    error("These tests require Julia at least v1.4")
end

@testset "StorageServer" begin
    include("tst_utils.jl")
    include("tst_server_utils.jl")
    include("tst_mirror_tarball.jl")
end
