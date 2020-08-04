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
- `show_progress::Bool`: `true` to show an additional progress meter. By default it is `true`.
- `timeout::Real`: specify the maximum building time (seconds) for each package. 
    Incremental building can use a smaller one to make sure task doesn't hangs. By default it is `7200`.

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
        timeout = 7200,
)
    upstreams = normalize_upstream.(upstreams)
    uuid = registry.uuid
    name = registry.name
    latest_hash = query_latest_hash(registry, upstreams)

    if isnothing(latest_hash)
        @error "failed to get registry from upstreams" registry = registry.name upstreams=upstreams
        return nothing
    end

    # fetch registry tarball
    resource = "/registry/$(uuid)/$(latest_hash)"
    tarball = joinpath(static_dir, "registry", uuid, latest_hash)
    download_and_verify(upstreams, resource, tarball; http_parameters=http_parameters) || return nothing
    
    packages = mktempdir() do tmpdir
        open(tarball, "r") do io
            Tar.extract(decompress(io), tmpdir)
        end
        read_packages(tmpdir; static_dir=static_dir, fetch_full_registry=!incremental_build)
    end

    if isempty(packages)
        @info "No new packages, skip this build"
        return latest_hash
    end

    num_versions = mapreduce(x -> length(x.versions), +, packages)
    upstream_str = join(upstreams, ", ")
    @info "Start pulling" date=now() name=name uuid=uuid hash=latest_hash num_versions=num_versions upstreams=upstream_str
    p = show_progress ? Progress(num_versions) : nothing
    mirror_tarball(packages, upstreams, static_dir; pkg_timeout=timeout, progress=p, http_parameters=http_parameters)

    # update /registries after updates
    registries_file = joinpath(static_dir, "registries")
    update_registries(registries_file, uuid, latest_hash)

    return latest_hash
end

function mirror_tarball(
        pkgs::AbstractVector{<:Package},
        upstreams::AbstractVector,
        static_dir::AbstractString;
        pkg_timeout = 7200,
        kwargs...
)
    ThreadPools.@qthreads for pkg in pkgs
        try
            timeout_call(pkg_timeout) do 
                mirror_tarball(pkg, upstreams, static_dir; kwargs...)
            end
        catch err
            err isa InterruptException && rethrow(err)
            @warn err
        end
    end
end


function mirror_tarball(
    pkg::Package,
    upstreams::AbstractVector,
    static_dir::AbstractString;
    progress::Union{Nothing, Progress} = nothing,
    http_parameters::Dict{Symbol, Any} = Dict{Symbol, Any}(),
    kwargs...
)
    uuid = pkg.uuid
    _mirror_artifact(hash) = mirror_tarball(Artifact(hash), upstreams, static_dir; kwargs...)

    for (ver, hash_info) in pkg.versions
        println("Info: $(now())\t $(pkg.name)@$(ver)")

        tree_hash = hash_info["git-tree-sha1"]

        resource = "/package/$(uuid)/$(tree_hash)"
        tarball = joinpath(static_dir, "package", uuid, tree_hash)

        download_and_verify(upstreams, resource, tarball; http_parameters=http_parameters) || continue

        # download artifacts
        mktempdir() do tmp_dir
            artifact_toml_paths = String[]
            open(tarball, "r") do io
                # only extract [Julia]Artifacts.toml files
                Tar.extract(decompress(io), tmp_dir) do hdr
                    if splitpath(hdr.path)[end] in artifact_names
                        push!(artifact_toml_paths, hdr.path)
                        return true
                    else
                        return false
                    end
                end
            end

            for path in artifact_toml_paths
                sys_path = joinpath(tmp_dir, path)
                artifacts = TOML.parsefile(sys_path)

                for (key, artifact_info) in artifacts
                    try
                        if artifact_info isa Dict
                            # platform independent artifacts
                            _mirror_artifact(artifact_info["git-tree-sha1"])
                        elseif artifact_info isa AbstractVector
                            # platform dependent artifacts
                            foreach(artifact_info) do x
                                _mirror_artifact(x["git-tree-sha1"])
                            end
                        else
                            @error "invalid artifact toml" package=pkg version=ver artifact=artifact_info
                        end
                    catch err
                        err isa InterruptException && rethrow(err)
                        err isa TimeoutException && rethrow(err)

                        # Failing to download artifact is not fatal, but we still need to tag this version tarball
                        # as incomplete and remove it. This makes incremental buidling much easier to handle
                        rm(tarball, force=true)
                        @warn "remove package tarball due to incomplete artifact downloading" uuid=uuid hash=tree_hash

                        rethrow(err)
                    end
                end
            end
        end

        if !isnothing(progress)
            ProgressMeter.next!(
                progress;
                showvalues = [(:package, pkg.name), (:version, ver)],
            )
        end
    end
end

function mirror_tarball(
        artifact::Artifact,
        upstreams::AbstractVector{<:AbstractString},
        static_dir::AbstractString;
        kwargs...
)
    resource = "/artifact/$(artifact.hash)"
    tarball = joinpath(static_dir, "artifact", artifact.hash)

    # an artifact can be used by different package versions or packages,
    # skip downloading if this artifact already exists
    isfile(tarball) && return nothing

    download_and_verify(upstreams, resource, tarball; kwargs...)
end

mirror_tarball(::Nothing, args...; kwargs...) = nothing


### helpers
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
