"""
    make_tarball(registry::AbstractString;
                 packages,
                 show_progress=true,
                 static_dir=STATIC_DIR,
                 clones_dir=CLONES_DIR)

Generating all static contents for registry `registry`.

After building, all static content data are saved to `static_dir`:

* `/registries`: map of registry uuids at this server to their current tree hashes
* `/registry/\$uuid/\$hash`: tarball of registry uuid at the given tree hash
* `/package/\$uuid/\$hash`: tarball of package uuid at the given tree hash
* `/artifact/\$hash`: tarball of an artifact with the given tree hash


# Keyword parameters

- `packages::Vector{Package}`: If is provided, it only pulls data specified by `packages`. This list can be built
  using [`read_packages`](@ref).
- `show_progress::Bool`: `true` to show an additional progress meter. By default it is `true`.
- 'static_dir::String': where all static contents are saved to. By default it is "static".
- 'clones_dir::String': where the package repositories are cloned to. By default it is "clones".

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
    show_progress = true,
    static_dir = STATIC_DIR,
    clones_dir = CLONES_DIR,
)
    registry_root = get_registry_path(registry)
    reg_file = joinpath(registry_root, "Registry.toml")
    reg_data = TOML.parsefile(reg_file)

    # 1. generate registry tarball
    registry_hash = readchomp(`git -C $registry_root rev-parse 'HEAD^{tree}'`)
    registry = GitTree(registry_root, registry_hash)
    uuid = reg_data["uuid"]
    tarball = joinpath(static_dir, "registry", uuid, registry_hash)
    make_tarball(registry, tarball)
    update_registries(reg_data["uuid"], registry_hash; static_dir = STATIC_DIR)

    # So far the contents in static_dir already make a valid storage server
    # then we gradually downloads and build all needed tarballs while serving the contents.
    # However, this requires pkg client support multiple pkg servers, otherwise, it might give
    # up too quickly to use the fallback solution.

    # 2. generate package tarballs for source codes and artifacts
    packages = isnothing(packages) ? read_packages(registry_root) : packages
    p = show_progress ? Progress(mapreduce(x -> length(x.versions), +, packages)) : nothing
    Threads.@threads for pkg in packages
        make_tarball(pkg; static_dir = static_dir, clones_dir = clones_dir, progress = p)
    end

    # clean downloaded cache in tempdir
    foreach(readdir(tempdir(), join = true)) do path
        if isfile(path) && !isnothing(match(r"jl_(.*)-download\.\w*(\.sha256)?", path))
            rm(path; force = true)
        end
    end
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
