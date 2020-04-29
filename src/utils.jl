const compress(io::IO) = TranscodingStream(GzipCompressor(level = 9), io)
const decompress(io::IO) = TranscodingStream(GzipDecompressor(), io)

"""
    make_tarball(src_path, tarball)

tar and compress resource `src_path` as `tarball`
"""
function make_tarball(src_path::AbstractString, tarball::AbstractString)
    mkpath(dirname(tarball))
    open(tarball, write = true) do io
        close(Tar.create(src_path, compress(io)))
    end
    return tarball
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
    verify_tarball_hash(tarball, ref_hash::SHA1)

Verify tarball resource with reference hash `ref_hash`. Throw an error if hashes don't match.
"""
function verify_tarball_hash(tarball, ref_hash::SHA1)
    local real_hash
    mktempdir() do tmp_dir
        open(tarball) do io
            Tar.extract(decompress(io), tmp_dir)
        end
        real_hash = SHA1(Pkg.GitTools.tree_hash(tmp_dir))
        chmod(tmp_dir, 0o777, recursive = true) # useless ?
    end
    real_hash == ref_hash || error("""
        tree hash mismatch:
        - expected: $(ref_hash)
        - computed: $(hash)
        """)
    return true
end

# input => output
# "General" => "/path/to/General/"
# "/path/to/General/" => "/path/to/General/"
function get_registry_path(registry::AbstractString)
    if isdir(registry) && "Registry.toml" in readdir(registry)
        return registry
    end

    registries = filter(joinpath.(DEPOT_PATH, "registries", registry)) do path
        isdir(path) && "Registry.toml" in readdir(path)
    end
    if isempty(registries)
        error("$registry does not exists, try `]registry add $registry` first.")
    end
    return first(registries)
end
