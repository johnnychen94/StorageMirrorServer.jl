module StorageServer

using Pkg
using LibGit2

using Pkg: TOML
using Pkg.Artifacts: download_artifact, artifact_path
using Base: SHA1
using LibGit2: GitRepo, GitObject

using ProgressMeter

const STATIC_DIR = "static"
const CLONES_DIR = "clones"

export make_tarball, read_packages

include("utils.jl")

# `/registry`: map of registry uuids at this server to their current tree hashes
# `/registry/$uuid/$hash`: tarball of registry uuid at the given tree hash
# `/package/$uuid/$hash`: tarball of package uuid at the given tree hash
# `/artifact/$hash`: tarball of an artifact with the given tree hash

# a registry has many packages
# a package has many git trees (versions)
# a git tree has a copy of source codes and many artifacts
# an artifact has one or many files
include("artifact.jl")
include("gittree.jl")
include("package.jl")
include("registry.jl")

end # module
