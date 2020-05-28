# !/usr/bin/env julia
# This script builds/pulls all static contents needed by storage server.
#
# Usage:
#  1. make sure you've added StorageServer.jl
#  2. generate/pull all tarballs: `julia gen_static.jl`
#  3. set a cron job to run step 2 regularly
#
# Note:
#   * Initialization would typically take days, depending on the network bandwidth and CPU
#   * set `JULIA_NUM_THREADS` to use multiple threads
#
# Disk space requirements for a complete storage (increases over time):
#   * `STATIC_DIR`: at least 500GB
#   * `CLONES_DIR`: at least 20GB
#   * `DEPOT_DIR`: no more than 5GB (temporary files)

using StorageServer
using Pkg

# do a manual update to fetch latest registries
Pkg.update()

# Where temporary artifacts are saved to
const DEPOT_DIR = "/tmp/julia_depot" # need absolute path
pushfirst!(DEPOT_PATH, DEPOT_DIR)

# This holds all the data you need to set up a storage server
# For example, my nginx service serves all files in `/mnt/mirrors` as static contents using autoindex
const STATIC_DIR = "/mnt/mirrors/julia"

# Where git repos of packages are saved to, this can be reused in the next-round update
# For the usage of storage server, there's no need to serve these from HTTP
const CLONES_DIR = "/root/StorageServer/clones"

# fetch the latest version of registry
registry_root = "/root/StorageServer/registries/General"
if !isdir(registry_root)
    run(`git clone https://github.com/JuliaRegistries/General.git $registry_root`)
end
run(`git -C $registry_root fetch --all`)
run(`git -C $registry reset --hard origin/master`)


# only pull/mirror whatever upstream server provides
upstreams = ["pkg.julialang.org"]
mirror_tarball(registry_root, upstreams; static_dir = STATIC_DIR, clones_dir = CLONES_DIR)
# use `make_tarball` instead of `mirror_tarball` to build tarballs from scratch


# post-cleanup
# this might not be necessary, but sometimes there are tmp files left in `/tmp`
foreach(readdir(tempdir(), join = true)) do path
    if isfile(path) && !isnothing(match(r"jl_(.*)-download\.\w*(\.sha256)?", path))
        rm(path; force = true)
    end
end
