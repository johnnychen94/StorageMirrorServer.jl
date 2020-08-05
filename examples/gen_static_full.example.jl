#! /usr/bin/env julia
# This script builds/pulls all static contents needed by storage server.
#
# Usage:
#  1. make sure you've added StorageMirrorServer.jl
#  2. generate/pull all tarballs: `julia gen_static_full.jl`
#  3. set a cron job to run step 2 regularly
#
# Note:
#   * Initialization would typically take days, depending on the network bandwidth and CPU
#   * set `JULIA_NUM_THREADS` to use multiple threads
#   * if you find `Info: date pkg@version` over-verbose, you can redirect stdout to `/dev/null`
#
# Disk space requirements for a complete storage (increases over time):
#   * `STATIC_DIR`: at least 500GB, would be better to have more than 3TB free space

using StorageMirrorServer
using Pkg

# This holds all the data you need to set up a storage server
# For example, my nginx service serves all files in `/mnt/mirrors` as static contents using autoindex
output_dir = "julia"

# check https://status.julialang.org/ for available public storage servers
upstreams = [
    "https://mirrors.bfsu.edu.cn/julia/static",
    "https://kr.storage.juliahub.com",
    "https://us-east.storage.juliahub.com",
]

registries = [
    # (name, uuid, original_git_url)
    ("General", "23338594-aafe-5451-b93e-139f81909106", "https://github.com/JuliaRegistries/General")
]

# These are default parameter settings for StorageMirrorServer
# you can modify them accordingly to fit your settings
parameters = Dict(
    # set it to false to initialize the first build, or when there are tarballs missing
    # set it to true could significantly boost the incremental build by avoiding unncessary tarball extraction
    # CAVEAT: If we skip the tarball extraction, i.e., set this to true, then it is possible that artifacts
    # are missing and never get downloaded.
    :incremental_build => false,

    # timeout (seconds) for each package (not the whole mirror process)
    :timeout => 7200,

    # if needed, you can pass custom http parameters
    :http_parameters => Dict{Symbol, Any}(
        :retry => true,
        :retries => 2,
        :timeout => 600,
    ),

    # whether to show the progress bar
    :show_progress => true,
)

for reg in registries
    mirror_tarball(reg, upstreams, output_dir; parameters...)
end
