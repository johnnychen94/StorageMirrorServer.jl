"""
    GitTree(source_path, hash::SHA1)
"""
struct GitTree
    repo::GitRepo
    hash::SHA1
    version::VersionNumber
end
function GitTree(source_path::AbstractString, hash::AbstractString, version::AbstractString)
    GitTree(GitRepo(source_path), SHA1(hash), VersionNumber(version))
end

"""
    make_tarball(tree::GitTree, tarball; static_dir = STATIC_DIR)

Checkout and save `tree` as tarballs.

It saves two kinds of tarballs:

* the source code as `\$static_dir/package/\$uuid/\$hash`
* one or many artifacts as `\$static_dir/artifact/\$hash`
"""
function make_tarball(tree::GitTree, tarball::AbstractString; static_dir = STATIC_DIR)
    is_new_tarball = !isfile(tarball)
    is_new_tarball || return nothing

    # 1. make tarball for source codes
    try
        mktempdir() do src_path
            _checkout_tree(tree, src_path)
            make_tarball(src_path, tarball)
            verify_tarball_hash(tarball, tree.hash)
        end
    catch err
        @warn "Cannot checkout $name [$uuid] $tree_hash"
        return nothing
    end

    # 2. make tarballs for each artifacts
    for path in eachline(pipeline(get_decompress_cmd(tarball), `$TAR -t`))
        # NOTE: the above can't handle paths with newlines
        # doesn't seem to be a way to get tar to use \0 instead
        basename(path) in Pkg.Artifacts.artifact_names || continue

        extract = pipeline(get_decompress_cmd(tarball), `gtar -x -O $path`)
        artifacts = TOML.parse(read(extract, String))
        for (key, val) in artifacts
            if val isa Dict
                make_tarball(Artifact(val); static_dir = static_dir)
            elseif val isa Vector
                # e.g., MKL for different platforms
                foreach(val) do x
                    make_tarball(Artifact(x); static_dir = static_dir)
                end
            else
                @warn "invalid artifact file entry: $val"
            end
        end
    end
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
        run(`git -C $clone_dir remote update`)
        @goto again
    end
end
