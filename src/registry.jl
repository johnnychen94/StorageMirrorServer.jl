"""
    make_tarball(registry::AbstractString;
                 packages::Union{Nothing, AbstractVector{Package}} = nothing,
                 upstreams::AbstractVector = [],
                 show_progress = true,
                 static_dir = STATIC_DIR,
                 clones_dir = CLONES_DIR)

Generating all static contents for registry `registry`.

After building, all static content data are saved to `static_dir`:

* `/registries`: map of registry uuids at this server to their current tree hashes
* `/registry/\$uuid/\$hash`: tarball of registry uuid at the given tree hash
* `/package/\$uuid/\$hash`: tarball of package uuid at the given tree hash
* `/artifact/\$hash`: tarball of an artifact with the given tree hash


# Keyword parameters

- `packages::Vector{Package}` (Optional): If is provided, it only pulls data specified by
  `packages`. This list can be built using [`read_packages`](@ref).
- `upstreams`: It would try to download tarballs from the upstream pkg/storage server first.
  If upstream server doesn't have that, it would build the data from scratch.
- `download_only`: if set to true, it only builds the registry, while everything else are pulled
  from existing upstreams. If upstream servers doesn't serve a file, the file is skipped. By default
  it is `false`.
- `show_progress::Bool`: `true` to show an additional progress meter. By default it is `true`.
- `static_dir::String`: where all static contents are saved to. By default it is "static".
- `clones_dir::String`: where the package repositories are cloned to. By default it is "clones".

# Examples

Archive the whole General registry
```julia
make_tarball("General")
```

Only archive packages (and their dependencies) developed by Julia* org.

```julia
registry = "General"
pkgs = read_packages(registry) do pkg
    occursin("/Julia", pkg.url)
end

make_tarball(registry; packages = pkgs)
```
"""
function make_tarball(
    registry::AbstractString;
    packages::Union{AbstractVector{Package},Nothing} = nothing,
    upstreams::AbstractVector = [],
    download_only = false,
    show_progress = true,
    static_dir = get_static_dir(),
    clones_dir = get_clones_dir(),
)
    upstreams = get_upstream.(upstreams)
    if !isempty(upstreams)
        @info "use available mirroring upstreams" upstreams
    elseif download_only
        error("upstreams are required when `download_only==true`")
    end

    if is_default_depot_path()
        @warn "Using default DEPOT_PATH could easily fill up free disk spaces (especially for SSDs). You can set `JULIA_DEPOT_PATH` env before starting julia" DEPOT_PATH
    end


    registry_root = get_registry_path(registry)
    reg_file = joinpath(registry_root, "Registry.toml")
    reg_data = TOML.parsefile(reg_file)

    # 1. generate registry tarball
    check_registry(registry_root)

    registry_hash = readchomp(`git -C $registry_root rev-parse 'HEAD^{tree}'`)
    uuid = reg_data["uuid"]
    registry = GitTree(registry_root, uuid, registry_hash)
    tarball = joinpath(static_dir, "registry", uuid, registry_hash)
    make_tarball(
        registry,
        tarball;
        static_dir = static_dir,
        upstreams = [], # always build registry tarball
        download_only = download_only,
    )

    # 2. generate package tarballs for source codes and artifacts
    packages = isnothing(packages) ? read_packages(registry_root) : packages
    p = show_progress ? Progress(mapreduce(x -> length(x.versions), +, packages)) : nothing
    Threads.@threads for pkg in packages
        make_tarball(
            pkg;
            static_dir = static_dir,
            clones_dir = clones_dir,
            upstreams = upstreams,
            download_only = download_only,
            progress = p,
        )
    end

    # update /registries to tell pkg server the current version is now ready
    update_registries(uuid, registry_hash; static_dir = static_dir)

    return static_dir
end

# update `/registries` file
function update_registries(uuid, hash; static_dir = STATIC_DIR)
    # each line is recorded in format: `/registry/$uuid/$hash`
    get_uuid(line) = split(line, "/")[3]

    registries_file = joinpath(static_dir, "registries")
    if isfile(registries_file)
        registries = Dict(get_uuid(item) => item for item in readlines(registries_file))
    else
        registries = Dict()
    end
    registries[uuid] = "/registry/$uuid/$hash"
    open(registries_file, write = true) do io
        for (uuid, registry_path) in sort!(collect(registries))
            println(io, registry_path)
        end
    end
end

function mirror_tarball(registry::AbstractString, upstreams; kwargs...)
    make_tarball(registry; upstreams = upstreams, download_only = true, kwargs...)
end
