const COMPRESS_CMD = `gzip -9`
const DECOMPRESS_CMD = `gzcat`
const TAR = `gtar`
const TAR_OPTS = ```
    --format=posix
    --numeric-owner
    --owner=0
    --group=0
    --mode=go-w,+X
    --mtime=1970-01-01
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime,delete=mtime
    --no-recursion
```
# reproducible tarball options based on
# http://h2.jaguarpaw.co.uk/posts/reproducible-tar/

get_compress_cmd() = COMPRESS_CMD
get_decompress_cmd(gz_file::AbstractString) = `$DECOMPRESS_CMD $gz_file`
function get_tar_cmd(src_dir::AbstractString, paths_file::AbstractString)
    `$TAR $TAR_OPTS -cf - -C $src_dir --null -T $paths_file`
end
get_untar_cmd(out_dir::AbstractString) = `tar -C $out_dir -x`

"""
    make_tarball(src_path, dest_path)

tar and compress resource `src_path` as `dest_path`
"""
function make_tarball(src_path::AbstractString, dest_path::AbstractString)
    mkpath(dirname(dest_path))
    mktemp() do paths_file, io
        for path in get_tree_paths(src_path)
            # \0 corresponds to --null flag
            print(io, "$path\0")
        end
        close(io)
        open(dest_path, write = true) do io
            tar = get_tar_cmd(src_path, paths_file)
            compress = get_compress_cmd()
            run(pipeline(tar, compress, io))
        end
    end
end

"""
    get_tree_paths(root::AbstractString)

Return a list of sorted relative paths for dirs and files in `root`
"""
function get_tree_paths(root::AbstractString)
    paths = String[]
    for (subroot, dirs, files) in walkdir(root)
        path = subroot != root ? relpath(subroot, root) : ""
        for file in [dirs; files]
            push!(paths, joinpath(path, file))
        end
    end
    sort!(paths)
    return paths
end

"""
    verify_tarball_hash(tarball_path, ref_hash::SHA1)

Verify tarball resource with reference hash `ref_hash`. Throw an error if hashes don't match.
"""
function verify_tarball_hash(tarball_path, ref_hash::SHA1)
    local real_hash
    mktempdir() do tmp_dir
        decompress = get_decompress_cmd(tarball_path)
        untar = get_untar_cmd(tmp_dir)
        run(pipeline(decompress, untar))
        real_hash = SHA1(Pkg.GitTools.tree_hash(tmp_dir))
        chmod(tmp_dir, 0o777, recursive = true) # useless ?
    end
    real_hash == ref_hash || error("""
        tree hash mismatch:
        - expected: $(ref_hash.bytes)
        - computed: $(hash.bytes)
        """)
    return true
end
