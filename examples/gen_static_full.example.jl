# !/usr/bin/env julia
# This script builds/updates all static contents needed by storage server _from scratch._
#
# Usage:
#  1. make sure you've added StorageServer.jl
#  2. generate/update all tarballs: `julia --color=yes gen_static.jl`
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
const CLONES_DIR = "/root/StorageServer/clones"

make_tarball("General"; static_dir=STATIC_DIR, clones_dir=CLONES_DIR)
