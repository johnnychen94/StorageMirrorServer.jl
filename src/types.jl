struct RegistryMeta
    name::String
    uuid::String
    source_url::String
    latest_hash::Union{String, Nothing}
end
RegistryMeta(name, uuid, source_url) = RegistryMeta(name, uuid, source_url, nothing)

struct Package
    name::String
    uuid::String
    versions::Dict
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
        new(name, uuid, versions_info, url, registry_dir)
    end
end

struct Artifact
    hash::String
end
