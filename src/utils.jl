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
verify_tarball_hash(tarball, ref_hash::AbstractString) = verify_tarball_hash(tarball, SHA1(ref_hash))

# input => output
# "General" => "/path/to/General/"
# "/path/to/General/" => "/path/to/General/"
function get_registry_path(registry::AbstractString)
    is_valid_registry(registry) && return registry

    registries = filter(is_valid_registry, joinpath.(DEPOT_PATH, "registries", registry))
    if isempty(registries)
        error("$registry does not exists, try `]registry add $registry` first.")
    end
    return first(registries)
end

function is_valid_registry(registry::AbstractString)
    isdir(registry) || return false
    "Registry.toml" in readdir(registry) || return false

    # To fetch the hash of the current registry, it needs to be a git repo
    try
        GitRepo(registry)
    catch err
        err isa LibGit2.GitError && return false
        rethrow(err)
    end
    return true
end

function check_registry(registry::AbstractString)
    is_valid_registry(registry) || error("$registry is not a valid Git registry repo.")
end

function is_default_depot_path()
    haskey(ENV, "JULIA_DEPOT_PATH") && return false
    first(DEPOT_PATH) != abspath(homedir(), ".julia") && return false

    return true
end
