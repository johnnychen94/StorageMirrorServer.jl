"""
    Package(name, uuid, registry_dir)
"""
struct Package
    name::String
    uuid::String
    versions::Dict
    tarball::String
    url::String
    registry_dir::String

    function Package(name, uuid, registry_dir; latest_versions_num::Union{Nothing, Integer}=nothing)
        versions_info = TOML.parsefile(joinpath(registry_dir, "Versions.toml"))
        versions = sort!(collect(keys(versions_info)), rev=true, by=VersionNumber)
        versions = isnothing(latest_versions_num) ? versions : versions[1: min(length(versions), latest_versions_num)]
        versions_info = Dict(k=>versions_info[k] for k in versions)

        pkg_info = TOML.parsefile(joinpath(registry_dir, "Package.toml"))
        url = pkg_info["repo"]

        tarball = joinpath("package", uuid)
        new(name, uuid, versions_info, tarball, url, registry_dir)
    end
end

"""
    make_tarball(pkg::Package; static_dir=STATIC_DIR, clones_dir = CLONES_DIR)

Make tarballs of all versions and artifacts for package `pkg`.
"""
function make_tarball(pkg::Package; static_dir = STATIC_DIR, clones_dir = CLONES_DIR)
    # let callers handle the error

    # 1. clone repo
    clone_dir = joinpath(clones_dir, pkg.uuid)
    _clone_repo(pkg.url, clone_dir)

    # 2. make tarball for each version in the registry
    for (ver, info) in pkg.versions
        tree_hash = info["git-tree-sha1"]

        tree = GitTree(clone_dir, tree_hash, ver)
        tarball = joinpath(static_dir, pkg.tarball, tree_hash)

        try
            make_tarball(tree, tarball; static_dir = static_dir)
        catch err
            # failing to download resources for a specific version is acceptable
            # but we need to clean things up
            @warn err repo_path = LibGit2.path(tree.repo) tarball = tarball
            rm(tarball, force = true)
        end
    end

    # keep clone_dir because we'll need it for the next round of update
    return
end

function _clone_repo(repo_url, clone_dir)
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

    # TODO: use `LibGit2.clone
    process = run(`git clone --mirror $repo_url $clone_dir`, wait = false)
    is_clone_failure = false
    while process_running(process)
        elapsed = (time() - timeout_start)
        if elapsed > timeout
            is_clone_failure = true
            @debug("Terminating cloning $repo_url")
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
        # although `git clone` removes `clone_dir` at failure
        # manually remove it again as a safe net
        rm(clone_dir, recursive = true, force = true)
        @error "Cannot clone $name [$uuid]"
    end
end
