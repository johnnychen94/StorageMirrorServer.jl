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
- `incremental_build::Bool`: `false` to force a full scan of the registry and its artifacts, which can be CPU
   heavy and time-consuming. By default it is `true`.
- `packages::AbstractVector{Package}`: manually create and specify a set of packages that needed to be stored. This
   can be used to build only a partial of the complete storage. Check [`read_packages`](@ref read_packages) for how
   to build packages info. (Experimental)
- `retry_failed::Bool`: `failed_resources.txt` stores resource records that failed to download, set `retry_failed`
   to `true` to try to download these resources. By default it is `true`.
- `show_progress::Bool`: `true` to show an additional progress meter. By default it is `true`.

"""
mirror_tarball(registry::Tuple, args...; kwargs...) = mirror_tarball(RegistryMeta(registry...), args...;kwargs...)

function mirror_tarball(
        registry::RegistryMeta,
        upstreams::AbstractVector,
        static_dir::AbstractString;
        http_parameters::Dict{Symbol, Any} = Dict{Symbol, Any}(),
        incremental_build = true,
        packages::AbstractVector = [],
        show_progress = true,
        retry_failed = true,
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
    upstream_str = join(upstreams, ", ")
    function _download(resource, tarball; throw_warnings=true)
        download_and_verify(upstreams, resource, tarball; http_parameters=http_parameters, throw_warnings=throw_warnings)
    end

    # 1. query latest registry hash
    upstreams = normalize_upstream.(upstreams)
    latest_hash = query_latest_hash(registry, upstreams)
    if isnothing(latest_hash)
        @error "failed to get registry from upstreams" registry = registry.name upstreams=upstreams
        return nothing
    end

    # 2. fetch registry tarball
    resource = "/registry/$(uuid)/$(latest_hash)"
    tarball = joinpath(static_dir, "registry", uuid, latest_hash)
    _download(resource, tarball) || return nothing
    
    # 3. read and download `/package/$uuid/$hash`
    packages = mktempdir() do tmpdir
        open(tarball, "r") do io
            Tar.extract(decompress(io), tmpdir)
        end
        read_packages(tmpdir; static_dir=static_dir, fetch_full_registry=!incremental_build)
    end

    num_versions = mapreduce(x -> length(x.versions), +, packages)
    @info "Start mirrorring" date=now() registry=name uuid=uuid hash=latest_hash num_versions=num_versions upstreams=upstream_str

    p = show_progress ? Progress(num_versions; desc="$name: Pulling packages: ") : nothing
    ThreadPools.@qthreads for pkg in packages
        for (ver, hash_info) in pkg.versions
            tree_hash = hash_info["git-tree-sha1"]
            resource = "/package/$(pkg.uuid)/$(tree_hash)"
            tarball = joinpath(static_dir, "package", pkg.uuid, tree_hash)
            
            try
                _download(resource, tarball) || log_to_failure(resource, static_dir)
            catch err
                @warn err
            end

            isnothing(p) || ProgressMeter.next!(p; showvalues = [(:package, pkg.name), (:version, ver)])
        end
    end

    # 4. read and download `/artifact/$hash`
    artifacts = query_artifacts(static_dir)
    p = show_progress ? Progress(length(artifacts); desc="$name: Pulling artifacts: ") : nothing
    ThreadPools.@qthreads for artifact in artifacts
        if is_valid(artifact)
            resource = "/artifact/$(artifact.hash)"
            tarball = joinpath(static_dir, "artifact", artifact.hash)

            try
                _download(resource, tarball) || log_to_failure(resource, static_dir)
            catch err
                @warn err
            end
            
            isnothing(p) || ProgressMeter.next!(p; showvalues = [(:artifact, artifact.hash)])
        end
    end

    # try to download failed resource
    failed_logfile = joinpath(static_dir, "failed_resources.txt")
    if isfile(failed_logfile)
        records = Set(readlines(failed_logfile))

        failed_record = String[]
        if retry_failed
            p = show_progress ? Progress(length(records); desc="$name: Re-pulling failed resources: ") : nothing

            ThreadPools.@qthreads for resource in records
                if !isnothing(match(resource_re, resource))
                    tarball = joinpath(static_dir, resource[2:end]) # note: joinpath(pwd(), "/a") == "/a"
                    try
                        mkpath(dirname(tarball))
                        _download(resource, tarball; throw_warnings=false) || push!(failed_record, resource)
                    catch err
                        # these are very likely to fail again
                        @debug err
                        push!(failed_record, resource)
                    end
                else
                    @warn "invalid resource" resource=resource file=failed_logfile
                end
                isnothing(p) || ProgressMeter.next!(p; showvalues = [(:resource, resource)])
            end
        else
            # remove duplicated records
            append!(failed_record, records)
        end

        sleep(0.2) # unsure why, but this fixes an UndefRefError error
        open(failed_logfile, "w") do io
            foreach(x->println(io, x), failed_record)
        end
    end


    # update /registries after updates
    registries_file = joinpath(static_dir, "registries")
    update_registries(registries_file, uuid, latest_hash)

    return latest_hash
end

### helpers
function log_to_failure(resource::AbstractString, static_dir::AbstractString)
    try
        logfile = joinpath(static_dir, "failed_resources.txt")
        open(logfile, "a"; lock=true) do io
            println(io, resource)
        end
    catch err
        @warn err
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

function query_artifacts(static_dir)
    cache_root = joinpath(static_dir, ".cache")
    package_re = Regex("package/($uuid_re)/($hash_re)")
    tarball_glob_pattern = ["package", Regex(uuid_re), Regex(hash_re)]
    artifact_glob_pattern = ["package", Regex(uuid_re), Regex(hash_re), r"[Julia]?Artifacts\.toml"]

    # incrementally extract Artifacts.toml
    ThreadPools.@qthreads for pkg_tarball in glob(tarball_glob_pattern, static_dir)
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
                push!(all_artifacts, Artifact(artifact_info["git-tree-sha1"]))
            elseif artifact_info isa AbstractVector
                # platform dependent artifacts, e.g., FFTW_jll
                append!(all_artifacts, map(x->Artifact(x["git-tree-sha1"]), artifact_info))
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
