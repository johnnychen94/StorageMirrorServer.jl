module StorageMirrorServer

using Random

using Glob

using Pkg
using Pkg: TOML
using Pkg.Artifacts: artifact_names

using Tar
using CodecZlib: GzipCompressor, GzipDecompressor
using TranscodingStreams: TranscodingStream

using HTTP

using ThreadPools

using Dates
using ProgressMeter

compress(io::IO) = TranscodingStream(GzipCompressor(level = 9), io)
decompress(io::IO) = TranscodingStream(GzipDecompressor(), io)

const default_http_parameters = Dict(
    :retry => false,
    :retries => 1,
    :timeout => 1200,
)

export mirror_tarball, read_packages

include("types.jl")
include("utils/utils.jl")
include("utils/server_utils.jl")
include("utils/registry_utils.jl")

include("mirror_tarball.jl")

end # module
