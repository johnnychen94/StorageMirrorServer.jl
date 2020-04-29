"""
    make_tarball(registry::AbstractString;
                 packages,
                 static_dir=STATIC_DIR,
                 clones_dir=CLONES_DIR)

Make tarballs for registry `registry`.

Three kinds of tarballs will be made:

* registry saved as `\$static_dir/registry/\$uuid/\$hash`
* all packages in the registry
  * all versions of package
    * artifacts saved as `\$static_dir/artifact/\$hash`
    * source codes saved as `\$static_dir/package/\$uuid/\$hash`

The current registry hash is recorded into `\$static_dir/registries` as a reference.

# Keyword parameters

- `packages::Vector{Package}`: If is provided, it only pulls data specified by `packages`. This list can be built
  using [`read_packages`](@ref).
- 'static_dir::String': where all static contents are saved to. By default it is "static".
- 'clones_dir::String': where the package repositories are cloned to. By default it is "clones".
- 'mirror::Bool': if it is `true`, then it will try to download the static data directly from upstream servers.
  If there's no upstream server or the download fails, it tries to build tarballs from scratch.



# Example

Archive the whole General registry
```julia
make_tarball("General")
```

Only archive packages (and their dependencies) developed by JuliaImages org.

```julia
registry = "General"
pkgs = read_packages(registry) do pkg
    occursin("JuliaImages", pkg.url)
end

make_tarball(registry; packages = pkgs)
```
"""
function make_tarball(
    registry::AbstractString;
    packages::Union{AbstractVector{Package}, Nothing} = nothing,
    mirror = true,
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

    # 2. generate package tarballs for source codes and artifacts
    packages = isnothing(packages) ? read_packages(registry_root) : packages
    p = Progress(mapreduce(x->length(x.versions), +, packages))
    for pkg in packages
        make_tarball(pkg; static_dir = static_dir, clones_dir = clones_dir, progress=p)
    end

    # 3. update registry file
    # records the latest hash of each registry: `/registry/$uuid/$hash`
    registries_file = joinpath(static_dir, "registries")
    if isfile(registries_file)
        registries =
            Dict(split(item, "/")[3] => item for item in readlines(registries_file))
    else
        registries = Dict()
    end
    uuid = reg_data["uuid"]
    registries[uuid] = "/registry/$uuid/$registry_hash"
    open(registries_file, write = true) do io
        for (uuid, registry_path) in sort!(collect(registries))
            println(io, registry_path)
        end
    end

    return nothing
end


"""
    read_packages(registry::AbstractString)::Vector{Package}; kwargs...)
    read_packages(f, registry; recursive=true, kwargs...)

Read all packages stored in registry `registry`.

If predicate function `f` is given, package that satisfies `f(pkg)==true` is put
into the return list. If `recursive==true`, then all dependency packages are also
added to the return list.

Kerword arguments:

- `latest_versions_num::Integer`: only get the latest `latest_versions_num` versions for each package

# Examples

```julia
    pkgs = read_packages(general) do pkg
        occursin("JuliaImages", pkg.url)
    end
```
"""
function read_packages(
    registry::AbstractString;
    latest_versions_num::Union{Nothing,Integer} = nothing,
)
    registry_root = get_registry_path(registry)
    reg_file = joinpath(registry_root, "Registry.toml")
    packages_data = TOML.parsefile(reg_file)["packages"]

    pkgs = [
        Package(
            info["name"],
            uuid,
            joinpath(registry_root, info["path"]),
            latest_versions_num = latest_versions_num,
        ) for (uuid, info) in packages_data
    ]
end

function read_packages(f, registry::AbstractString; recursive = true, kwargs...)
    all_packages = read_packages(registry; kwargs...)
    init_pkgs = filter(f, all_packages)

    recursive || return init_pkgs

    pkgs = collect(init_pkgs)
    foreach(init_pkgs) do pkg
        append_deps!(pkgs, pkg, all_packages)
    end
    return pkgs
end

"""
    append_deps!(pkgs, pkg, full_pkglist)

Recursively find dependency packages of `pkg` and append them into `pkgs`.
"""
function append_deps!(
    pkgs::AbstractVector{Package},
    pkg::Package,
    full_pkglist::AbstractVector{Package},
)
    deps_file = joinpath(pkg.registry_dir, "Deps.toml")
    isfile(deps_file) || return pkgs

    dep_info = TOML.parsefile(deps_file)
    isempty(dep_info) && return pkgs

    # NOTE:
    # This doesn't check versions info, just returns all packages listed in Deps.toml
    dep_pkgs_names = mapreduce(Set, union, keys.(values(dep_info)))
    init_pkgs = filter(full_pkglist) do pkg
        pkg.name in dep_pkgs_names && !(pkg in pkgs)
    end
    append!(pkgs, init_pkgs)

    isempty(init_pkgs) && return pkgs

    foreach(init_pkgs) do pkg
        append_deps!(pkgs, pkg, full_pkglist)
    end
    return pkgs
end

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
