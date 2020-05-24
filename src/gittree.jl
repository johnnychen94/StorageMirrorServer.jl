"""
    GitTree(source_path, uuid, hash::SHA1, version)
"""
struct GitTree
    repo::GitRepo
    clone_dir::String
    uuid::String
    hash::SHA1
    # registries don't have version info
    version::Union{VersionNumber,Nothing}
end
function GitTree(
    source_path::AbstractString,
    uuid::AbstractString,
    hash::AbstractString,
    version::Union{AbstractString,Nothing} = nothing,
)
    version = isnothing(version) ? version : VersionNumber(version)
    GitTree(GitRepo(source_path), source_path, uuid, SHA1(hash), version)
end

"""
    make_tarball(tree::GitTree, tarball;
                 static_dir = STATIC_DIR,
                 upstreams = [],
                 download_only = false)

Checkout and save `tree` as tarballs.

It saves two kinds of tarballs:

* the source code of current git tree as `\$static_dir/package/\$uuid/\$hash`
* one or many artifacts as `\$static_dir/artifact/\$hash`
"""
function make_tarball(
    tree::GitTree,
    tarball::AbstractString;
    static_dir = get_static_dir(),
    upstreams::AbstractVector = [],
    download_only = false,
)
    # 1. make tarball for source codes
    resource = "/package/$(tree.uuid)/$(tree.hash)"

    try
        if !any(x -> download_and_verify(x, resource, tarball), upstreams)
            if download_only && !isnothing(tree.version)
                @warn "failed to fetch tarball $resource"
            end

            # build tarball from scratch
            # always build tarball for registry
            mktempdir() do src_path
                _checkout_tree(tree, src_path)
                make_tarball(src_path, tarball)
                verify_tarball_hash(tarball, tree.hash)
            end
        end
    catch err
        @warn "Cannot checkout $(tree.version)" err
        return nothing
    end

    # 2. make tarballs for each artifacts
    tmp_dir, paths = open(tarball) do io
        paths = String[]
        Tar.extract(decompress(io)) do hdr
            if split(hdr.path, '/')[end] in artifact_names
                push!(paths, hdr.path)
                return true
            else
                return false
            end
        end, paths
    end
    for path in paths
        sys_path = joinpath(tmp_dir, path)
        artifacts = TOML.parsefile(sys_path)
        for (key, artifact_info) in artifacts
            # Use non-throw version `artifact_no_throw` because we don't have control of
            # what Artifact.toml could be in each repository.
            if artifact_info isa Dict
                make_tarball(
                    artifact_no_throw(artifact_info);
                    static_dir = static_dir,
                    upstreams = upstreams,
                    download_only = download_only,
                )
            elseif artifact_info isa Vector
                # e.g., MKL for different platforms
                foreach(artifact_info) do x
                    make_tarball(
                        artifact_no_throw(x);
                        static_dir = static_dir,
                        upstreams = upstreams,
                        download_only = download_only,
                    )
                end
            else
                @warn "invalid artifact file entry: $(artifact_info)"
            end
        end
    end
    rm(tmp_dir, recursive = true)
end

function _checkout_tree(tree::GitTree, target_directory)
    opts = LibGit2.CheckoutOptions(
        checkout_strategy = LibGit2.Consts.CHECKOUT_FORCE,
        target_directory = Base.unsafe_convert(Cstring, target_directory),
    )

    retry = true
    @label again
    try
        LibGit2.checkout_tree(
            tree.repo,
            GitObject(tree.repo, string(tree.hash)),
            options = opts,
        )
    catch err
        retry || rethrow(err)

        retry = false
        run(`git -C $(tree.clone_dir) remote update`)
        @goto again
    end
end
