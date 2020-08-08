"""
    read_packages(registry::AbstractString; kwargs...)
    read_packages(f, registry; recursive=true, kwargs...)

Read all packages stored in registry `registry`.

If predicate function `f` is given, package that satisfies `f(pkg)==true` is put
into the return list. If `recursive==true`, then all dependency packages are also
added to the return list.

Kerword arguments:

- `latest_versions_num::Integer`: only get the latest `latest_versions_num` versions for each package.
- `fetch_full_registry::Bool = false`: `true` to disable incremental parsing.

# Examples

List all packages:

```julia
pkgs = read_packages("General")
```

List only packages under JuliaArrays:

```julia
pkgs = read_packages("General") do pkg
    occursin("JuliaArrays", pkg.url)
end
```
"""
function read_packages(
    registry_root::AbstractString;
    latest_versions_num::Union{Nothing,Integer} = nothing,
    static_dir = nothing,
    fetch_full_registry = false
)
    reg_file = joinpath(registry_root, "Registry.toml")
    reg_info = TOML.parsefile(reg_file)

    pkgs = [
        Package(
            info["name"],
            uuid,
            joinpath(registry_root, info["path"]),
            latest_versions_num = latest_versions_num,
        ) for (uuid, info) in reg_info["packages"]
    ]

    if !fetch_full_registry && !isnothing(static_dir)
        # If a certain version is already built, then skip that version without downloading and extracting.
        # Even if not downloaded, artifacts of that version will be skipped, too.
        for pkg in pkgs
            uuid = pkg.uuid
            for (ver, hash_info) in pkg.versions
                hash = hash_info["git-tree-sha1"]
        
                tarball = joinpath(static_dir, "package", uuid, hash)
                isfile(tarball) && delete!(pkg.versions, ver)
            end
        end
        pkgs = [pkg for pkg in pkgs if !isempty(pkg.versions)]
    end

    sort!(pkgs, by = x -> x.name)

    return pkgs
end

function read_packages(f, registry_root::AbstractString; recursive = true, kwargs...)
    all_packages = read_packages(registry_root; kwargs...)
    init_pkgs = filter(f, all_packages)

    recursive || return init_pkgs

    pkgs = collect(init_pkgs)
    foreach(init_pkgs) do pkg
        append_deps!(pkgs, pkg, all_packages)
    end
    sort!(pkgs, by = x -> x.name)

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
