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
    # if needed, you can pass custom http parameters
    :http_parameters => Dict{Symbol, Any}(
        :retry => true,
        :retries => 2,
        :timeout => 7200,
        # download data using proxy
        # it also respects `http_proxy`, `https_proxy` and `no_proxy` environment variables
        # :proxy => "http://localhost:1080"
    ),

    # whether to show the progress bar
    :show_progress => true,

    # This script generates a `failed_resource.txt` that records failed-to-downloaded files. Some of
    # these have already disappears in the network and no longer available. By default, items in
    # this file are skipped in next 24 hours. You can configure `skip_duration` to make it larger.
    # Or, you could manually create a `blocklist.txt` to permanently skip them.
    :skip_duration => 24
)

for reg in registries
    mirror_tarball(reg, upstreams, output_dir; parameters...)
end
