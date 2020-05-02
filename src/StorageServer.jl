module StorageServer

using Base: SHA1
using Random

using Pkg
using Pkg: TOML
using Pkg.Artifacts: download_artifact, artifact_path, artifact_names

using LibGit2
using LibGit2: GitRepo, GitObject

using Tar
using CodecZlib: GzipCompressor, GzipDecompressor
using TranscodingStreams: TranscodingStream

using HTTP

using Dates
using ProgressMeter


const STATIC_DIR = "static"
const CLONES_DIR = "clones"

export make_tarball, mirror_tarball, read_packages

include("utils.jl")
include("resources.jl") # modified from PkgServer.jl

# a registry has many packages
# a package has many git trees (versions)
# a git tree has a copy of source codes and many artifacts
# an artifact has one or many files
include("artifact.jl")
include("gittree.jl")
include("package.jl")
include("registry.jl")

end # module
