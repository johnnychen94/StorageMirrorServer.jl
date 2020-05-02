"""
    Package(name, uuid, registry_dir; [latest_versions_num::Integer])
"""
struct Package
    name::String
    uuid::String
    versions::Dict
    tarball::String
    url::String
    registry_dir::String

    function Package(
        name::AbstractString,
        uuid::AbstractString,
        registry_dir::AbstractString;
        latest_versions_num::Union{Nothing,Integer} = nothing,
    )
        isdir(registry_dir) || error("Folder $registry_dir doesn't exist.")

        version_file = joinpath(registry_dir, "Versions.toml")
        isfile(version_file) ||
        error("$version_file doesn't exist: $registry_dir might be a broken registry folder.")

        versions_info = TOML.parsefile(version_file)
        if !isnothing(latest_versions_num)
            # only keep the latest `latest_versions_num` versions
            versions = sort!(collect(keys(versions_info)), rev = true, by = VersionNumber)
            versions = versions[1:min(length(versions), latest_versions_num)]
            versions_info = Dict(k => versions_info[k] for k in versions)
        end

        dep_file = joinpath(registry_dir, "Package.toml")
        isfile(dep_file) ||
        error("$dep_file doesn't exist: $registry_dir might be a broken registry folder.")
        pkg_info = TOML.parsefile(dep_file)

        url = pkg_info["repo"]
        tarball = joinpath("package", uuid)
        new(name, uuid, versions_info, tarball, url, registry_dir)
    end
end

"""
    make_tarball(pkg::Package;
                 static_dir = STATIC_DIR,
                 clones_dir = CLONES_DIR
                 upstreams = [],
                 download_only = false)

Make tarballs for all versions and artifacts of package `pkg`.
"""
function make_tarball(
    pkg::Package;
    upstreams::AbstractVector = [],
    download_only = false,
    static_dir = STATIC_DIR,
    clones_dir = CLONES_DIR,
    progress::Union{Nothing,Progress} = nothing,
)
    # 1. clone repo
    clone_dir = joinpath(clones_dir, pkg.uuid)
    try
        _clone_repo(pkg, clone_dir)
    catch err
        # although `git clone` removes `clone_dir` at failure
        # here we manually remove it again for safety
        rm(clone_dir, recursive = true, force = true)
        @warn err name = pkg.name uuid = pkg.uuid
        return
    end
    isdir(clone_dir) || return

    # 2. make tarball for each version in the registry
    for (ver, info) in pkg.versions
        tree_hash = info["git-tree-sha1"]

        tree = GitTree(clone_dir, pkg.uuid, tree_hash, ver)
        tarball = joinpath(static_dir, pkg.tarball, tree_hash)

        try
            if !isnothing(progress)
                # although it doesn't get updated if this function return early,
                # an approximate progress would already be useful enough
                ProgressMeter.next!(
                    progress;
                    showvalues = [(:package, pkg.name), (:version, ver)],
                )
            end

            make_tarball(
                tree,
                tarball;
                static_dir = static_dir,
                upstreams = upstreams,
                download_only = download_only,
            )

            @info "$(now())\t$(pkg.name)@$(ver)"
        catch err
            err isa InterruptException && rethrow(err)
            # failing to download resources for a specific version is acceptable
            # but we need to clean things up
            @warn err repo_path = LibGit2.path(tree.repo) tarball = tarball
            rm(tarball, force = true)
        end
    end

    # keep clone_dir because we'll need it for the next round of update
    return
end

function _clone_repo(pkg::Package, clone_dir)
    isdir(clone_dir) && return

    timeout_start = time()
    # package in registry is expected to be unavailable for several reasons:
    #   * a private repository that you don't have access to
    #   * package owner deleted that repository after registration
    #   * unstable network connection

    # wait `timeout` seconds before sending a SIGTERM signal to clone process,
    # then waits another `kill_timeout` seconds before sending a SIGKILL signal
    timeout = 720
    kill_timeout = 60

    if startswith(lowercase(pkg.url), "http")
        try
            HTTP.request("GET", pkg.url)
        catch err
            if err isa HTTP.ExceptionRequest.StatusError
                @warn "failed to request $(pkg.url): $(pkg.name) might not exist or is not public."
                return
            end
        end
    end

    # TODO: use `LibGit2.clone` ?
    process = run(`git clone --mirror $(pkg.url) $clone_dir`, wait = false)
    is_clone_failure = false
    while process_running(process)
        elapsed = (time() - timeout_start)
        if elapsed > timeout
            is_clone_failure = true
            @debug("Terminating cloning $(pkg.url)")
            kill(process)
            start_time = time()
            while process_running(process)
                @debug "waiting for process to terminate"
                if time() - start_time > kill_timeout
                    kill(process, Base.SIGKILL)
                end
                sleep(1)
            end
        end
        sleep(1)
    end

    if is_clone_failure
        @error "Cannot clone $(pkg.name) [$(pkg.uuid)]"
    end
end



"""
    read_packages(registry::AbstractString)::Vector{Package}; kwargs...)
    read_packages(f, registry; recursive=true, kwargs...)

Read all packages stored in registry `registry`.

If predicate function `f` is given, package that satisfies `f(pkg)==true` is put
into the return list. If `recursive==true`, then all dependency packages are also
added to the return list.

Kerword arguments:

- `latest_versions_num::Integer`: only get the latest `latest_versions_num` versions for each package.

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
    sort!(pkgs, by = x -> x.name)

    return pkgs
end

function read_packages(f, registry::AbstractString; recursive = true, kwargs...)
    all_packages = read_packages(registry; kwargs...)
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
