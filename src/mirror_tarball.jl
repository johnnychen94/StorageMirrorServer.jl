"""
    mirror_tarball(registry, upstreams::AbstractVector, static_dir::String; kwargs...)

Generating all static contents for registry `registry`.

After building, all static content data are saved to `static_dir`:

* `/registries`: map of registry uuids at this server to their current tree hashes
* `/registry/\$uuid/\$hash`: tarball of registry uuid at the given tree hash
* `/package/\$uuid/\$hash`: tarball of package uuid at the given tree hash
* `/artifact/\$hash`: tarball of an artifact with the given tree hash

Set environment variable `JULIA_NUM_THREADS` to enable multi-threads.

# Keyword parameters

- `http_parameters::Dict{Symbol, Any}`: any parameters that need to pass to `HTTP.get` when fetching resources.
- `packages::AbstractVector{Package}`: manually create and specify a set of packages that needed to be stored. This
   can be used to build only a partial of the complete storage. Check [`read_packages`](@ref read_packages) for how
   to build packages info.
- `show_progress::Bool`: `true` to show an additional progress meter. By default it is `true`.
- `skip_duration::Real`: specify for how long (hours) you want to skip the resources listed in `/failed_resources.txt`
   until the next try of them. By default it is `24` hours.

"""
mirror_tarball(registry::Tuple, args...; kwargs...) = mirror_tarball(RegistryMeta(registry...), args...;kwargs...)

function mirror_tarball(
        registry::RegistryMeta,
        upstreams::AbstractVector,
        static_dir::AbstractString;
        http_parameters::Dict{Symbol, Any} = Dict{Symbol, Any}(),
        packages::Union{AbstractVector, Nothing} = nothing,
        registry_hash::Union{AbstractString, Nothing} = nothing,
        skip_duration = 24,
        show_progress = true,
)
    ### Except for the complex error handling strategy, the mirror routine
    ###   1. query upstreams to get the latest hash 
    ###   2. fetch registry tarball and save it as `registry/$uuid/$hash`
    ###   3. read pacakges information from registry tarball, download and save all packages (but not
    ###      their artifacts) to `packages/$uuid/$hash`
    ###   4. decompress and extract `*Artifacts.toml` files from each tarball in
    ###      `packages/$uuid/$hash`, and download all artifacts to `artifact/$hash`
    ###   5. update `/registries` so that downstream Pkg client/server knows that
    ###
    ### There will be some caching files:
    ###   * `/failed_resources.txt` records resources that failed to download in the previous mirror
    ###     routine
    ###   * `.cache/package/$uuid/$hash/*Artifacts.toml` caches all `*Artifacts.toml` files so that
    ###     we don't need to waste the time and resources in decompressing and extracting them from
    ###     `/package/$uuid/$hash` -- This is a CPU and IO hotspot

    uuid = registry.uuid
    name = registry.name
    failed_logfile = joinpath(static_dir, "failed_resources.txt")
    upstream_str = join(upstreams, ", ")

    # Some resources vanishes and can never be downloaded, we skip them in the next 24 hours
    last_try_time = query_last_try_datetime(failed_logfile) 
    skipped = now() - last_try_time < Hour(skip_duration)
    skipped_records = skipped ? read_records(failed_logfile) : Set()
    function _download(resource, tarball; throw_warnings=true)
        if resource in skipped_records
            @info "fetching resource has failed in the last $skip_duration hours, skip it" resource date=now()
            return false
        end

        try
            show_progress && @info "downloading resource..." resource=resource tarball=tarball date=now()
            rst = download_and_verify(upstreams, resource, tarball; http_parameters=http_parameters, throw_warnings=throw_warnings)
            if rst !== false
                return true
            else
                show_progress && @info "skip resource fetching in next $skip_duration hours" resource date=now()
                log_to_failure(resource, failed_logfile)
                return false
            end
        catch err
            throw_warnings && @warn err resource=resource
            rm(tarball; force=true)
            show_progress && @info "skip resource fetching in next $skip_duration hours" resource date=now()
            log_to_failure(resource, failed_logfile)
            return false
        end
    end

    # 1. query latest registry hash
    upstreams = normalize_upstream.(upstreams)
    latest_hash = isnothing(registry_hash) ? query_latest_hash(registry, upstreams) : registry_hash
    if isnothing(latest_hash)
        @error "failed to query the latest registry hash" uuid=uuid hash=latest_hash upstreams=upstreams date=now()
        error("stop mirroring.")
    end

    # 2. fetch registry tarball
    resource = "/registry/$(uuid)/$(latest_hash)"
    tarball = joinpath(static_dir, "registry", uuid, latest_hash)
    rst = _download(resource, tarball)
    if !rst
        @error "failed to fetch registry tarball" uuid=uuid hash=latest_hash upstreams=upstreams date=now()
        error("stop mirroring.")
    end
    
    # 3. read and download `/package/$uuid/$hash`
    if isnothing(packages)
        packages = mktempdir() do tmpdir
            open(tarball, "r") do io
                Tar.extract(decompress(io), tmpdir)
            end
            # only returns packages that are not stored in static_dir
            read_packages(tmpdir; fetch_full_registry=false, static_dir=static_dir)
        end
    end

    num_versions = mapreduce(x -> length(x.versions), +, packages)
    @info "Start mirrorring" date=now() registry=name uuid=uuid hash=latest_hash num_versions=num_versions upstreams=upstream_str
    skipped && @info "$(length(skipped_records)) previously failed resources are skipped during this build" date=now()

    p = show_progress ? Progress(num_versions; desc="$name: Pulling packages: ") : nothing
    if !isempty(packages)
        ThreadPools.@qthreads for pkg in packages
            for (ver, hash_info) in pkg.versions
                tree_hash = hash_info["git-tree-sha1"]
                resource = "/package/$(pkg.uuid)/$(tree_hash)"
                tarball = joinpath(static_dir, "package", pkg.uuid, tree_hash)
                _download(resource, tarball)
                isnothing(p) || ProgressMeter.next!(p; showvalues = [(:date, now()), (:package, pkg.name), (:version, ver), (:uuid, pkg.uuid), (:hash, tree_hash)])
            end
        end
    end

    # 4. read and download `/artifact/$hash`
    # only returns artifacts that are not stored in static_dir
    @info "querying artifacts info, this may take some time..." date=now()
    artifacts = query_artifacts(static_dir; fetch_full=false)
    @info "found $(length(artifacts)) new artifacts" date=now()
    p = show_progress ? Progress(length(artifacts); desc="$name: Pulling artifacts: ") : nothing
    batch_size = min(length(artifacts), max(20, ceil(Int, length(artifacts)/(5*Threads.nthreads()))))
    if !isempty(artifacts)
        ThreadPools.@qthreads for artifact in artifacts
            if is_valid(artifact)
                tree_hash = artifact.hash
                resource = "/artifact/$(tree_hash)"
                tarball = joinpath(static_dir, "artifact", tree_hash)

                _download(resource, tarball)
                isnothing(p) || ProgressMeter.next!(p; showvalues = [(:date, now()), (:artifact, tree_hash), (:resource, resource), (:tarball, tarball)])
            end
        end
    end

    # update /registries after updates
    registries_file = joinpath(static_dir, "registries")
    update_registries(registries_file, uuid, latest_hash)

    # clean up
    # Glob.jl doesn't support ** syntax yet: https://github.com/vtjnash/Glob.jl/issues/19
    foreach(glob(glob"artifact/*.tmp.*", static_dir)) do tarball
        rm(tarball; force=true)
    end
    foreach(glob(glob"*/*/*.tmp.*", static_dir)) do tarball
        # /registry and /package
        rm(tarball; force=true)
    end

    last_try_time = skipped ? last_try_time : now()
    failed_records = read_records(failed_logfile)
    buffer = IOBuffer()
    println(buffer, last_try_time)
    foreach(failed_records) do resource
        if !isfile(joinpath(static_dir, resource[2:end])) # joinpath(pwd(), "/a") == "/a"
            println(buffer, resource)
        end
    end
    open(failed_logfile, "w") do io
        write(io, take!(buffer))
    end
    @info("Mirror completed. There are $(length(failed_records) - length(skipped_records)) new fail-to-fetch resources and will be skipped in the next $(skip_duration) hours.",
        date=now(), registry=name, uuid=uuid, hash=latest_hash, upstreams=upstream_str)

    return latest_hash
end

### helpers
function log_to_failure(resource::AbstractString, logfile)
    try
        if VERSION < v"1.5"
            open(logfile, "a") do io
                println(io, resource)
            end
        else
            open(logfile, "a"; lock=true) do io
                println(io, resource)
            end
        end
    catch err
        @warn err resource=resource
    end
end

function query_last_try_datetime(logfile)
    isfile(logfile) || return DateTime(0)

    line = readline(logfile)
    try
        return DateTime(line)
    catch err
        if err isa ArgumentError
            return DateTime(0)
        end
        rethrow(err)
    end
end

function read_records(logfile)
    isfile(logfile) || return Set()
    records = readlines(logfile)
    isempty(records) && return Set()

    filter(sort(collect(Set(records)))) do resource
        !isnothing(match(resource_re, resource))
    end
end

function update_registries(registries_file, uuid, hash)
    # each line is recorded in format: `/registry/$uuid/$hash`
    get_uuid(line) = split(line, "/")[3]

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

function query_artifacts(static_dir; fetch_full=false)
    cache_root = joinpath(static_dir, ".cache")
    package_re = Regex("package/($uuid_re)/($hash_re)")
    tarball_glob_pattern = ["package", Regex(uuid_re), Regex(hash_re)]
    artifact_glob_pattern = ["package", Regex(uuid_re), Regex(hash_re), r"[Julia]?Artifacts\.toml"]

    # incrementally extract Artifacts.toml
    ThreadPools.@qbthreads for pkg_tarball in glob(tarball_glob_pattern, static_dir)
        pkg_uuid, pkg_hash = match(package_re, pkg_tarball).captures
        cache_dir = joinpath(cache_root, "package", pkg_uuid, pkg_hash)

        with_cache_dir(cache_dir) do
            # if cache_dir already exists, skip the decompress and extract
            # https://github.com/johnnychen94/StorageMirrorServer.jl/issues/5
            mkpath(cache_dir)
            try
                open(pkg_tarball, "r") do io
                    Tar.extract(decompress(io), cache_dir) do hdr
                        splitpath(hdr.path)[end] in artifact_names
                    end
                end
            catch err
                @warn "failed to extract package tarball" uuid=pkg_uuid hash=pkg_hash
                rm(pkg_tarball; force=true) # remove it if this tarball is broken
                rm(cache_dir; force=true, recursive=true)
                return false
            end

            # Although not all package has `*Artifacts.toml`, we still keep the empty `cache_dir`
            # for them as a placeholder to notify `with_cache_dir` that it can directly use caches
            # and skip the extraction call
            return true # to notify with_cache_dir that this function call success
        end
    end

    # read all artifacts
    all_artifacts = Artifact[]
    for artifact_toml in glob(artifact_glob_pattern, cache_root)
        for (key, artifact_info) in TOML.parsefile(artifact_toml)
            if artifact_info isa Dict
                # platform independent artifacts, e.g., TestImages
                tree_hash = artifact_info["git-tree-sha1"]
                tarball = joinpath(static_dir, "artifact", tree_hash)
                if fetch_full || !isfile(tarball)
                    push!(all_artifacts, Artifact(tree_hash))
                end
            elseif artifact_info isa AbstractVector
                # platform dependent artifacts, e.g., FFTW_jll
                for x in artifact_info
                    tree_hash = x["git-tree-sha1"]
                    tarball = joinpath(static_dir, "artifact", tree_hash)
                    if fetch_full || !isfile(tarball)
                        push!(all_artifacts, Artifact(tree_hash))
                    end
                end
            else
                @warn "invalid artifact toml" package=pkg version=ver artifact=artifact_info
            end
        end
    end

    # the same artifacts might be recorded in multiple versions
    return Set(all_artifacts)
end

function is_valid(artifact::Artifact)
    isempty(artifact.hash) && return false

    return true
end
