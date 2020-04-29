"""
    Artifact(hash::SHA1, tarball::String, downloads::Vector)
    Artifact(info::Dict)
"""
struct Artifact
    hash::SHA1
    tarball::String
    downloads::Vector
end

function Artifact(info::Dict)
    hash = info["git-tree-sha1"]
    tarball = joinpath("artifact", hash)
    if haskey(info, "download")
        downloads = info["download"]
        downloads isa Vector || (downloads = [downloads])
    else
        downloads = []
    end
    Artifact(SHA1(hash), tarball, downloads)
end

"""
    make_tarball(artifact::Artifact; static_dir = STATIC_DIR)

Make a tarball for artifact `artifact` and save to `\$static_dir/artifact/\$hash`.
"""
function make_tarball(artifact::Artifact; static_dir = STATIC_DIR)
    tarball = joinpath(static_dir, artifact.tarball)

    # an artifact can be used by different package versions or packages,
    # skip downloading if this artifact already exists
    isfile(tarball) && return

    local src_path # the artifact dirpath in JULIA_DEPOT_PATH
    try
        src_path = _download(artifact)
        make_tarball(src_path, tarball)
        verify_tarball_hash(tarball, artifact.hash)

        # TODO: free up spaces? -- this may break current depot path
        # rm(src_path, force = true, recursive = true)
    catch err
        @warn err tarball = tarball
        @isdefined(src_path) && rm(src_path, force = true, recursive = true)
        rm(tarball, force = true)
    end
end

# This is a no-op if the package doesn't provide any download link for its artifacts.
# It is okay if the artifacts are downloaded during build stage, otherwise, those artifacts
# won't be downloaded.
# An example of this is can be found at:
#   https://github.com/JuliaImages/TestImages.jl/blob/eaa94348df619c65956e8cfb0032ecddb7a29d3a/src/TestImages.jl#L101
function _download(artifact::Artifact)
    for download in artifact.downloads
        url = download["url"]
        hash = download["sha256"]
        success = download_artifact(artifact.hash, url, hash, verbose = false)
        success || error("artifact download failed")
    end

    artifact_dirpath = artifact_path(artifact.hash, honor_overrides = false)
    isdir(artifact_dirpath) || error("artifact download failed")

    return artifact_dirpath
end
