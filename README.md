# StorageServer

[![Build Status](https://travis-ci.com/johnnychen94/StorageServer.jl.svg?branch=master)](https://travis-ci.com/johnnychen94/StorageServer.jl)
[![Codecov](https://codecov.io/gh/johnnychen94/StorageServer.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/johnnychen94/StorageServer.jl)

This package is used to set up a Julia Package Storage Server. The protocol details are
described in https://github.com/JuliaLang/Pkg.jl/issues/1377.

TL;DR; A storage server contains all the static contents you need to download when you do `]add PackageName`.

To set up a storage server, you'll need to:

1. get the static contents
2. serve them as a HTTP(s) service using nginx or whatever you like
3. set up a cron job to get regular update

This package is used to make "1. get the static contents" easy and stupid.

# Build from scratch

The following is the minimal codes you need to build static contents from scratch. It will creates
two folders in current folder:

* `static` holds all the data you need to set up a HTTP service.
* `clones` contains all git repositories of packages. It will be used in next round of update
(usually a cron job), so there's no need to remove it.

```julia
using StorageServer
using Pkg

# By default, artifacts are first downloaded to $HOME/.julia/artifacts
# Keeping all downloaded artifacts could easily consume TB level of disk spaces,
# so it's recommended to switch to a folder with enough disk spaces.
# An alternative is to set `JULIA_DEPOT_PATH` env before starting julia
const DEPOT_DIR = abspath("depot")
pushfirst!(DEPOT_PATH, DEPOT_DIR)

Pkg.update()

make_tarball("General")
```

> if the service serves a registry, it can serve all package versions referenced by that registry;
> if it serves a package version, it can serve all artifacts used by that package.

Although it does _not_ follow the completeness requirement of Storage protocol, it makes sense in 
some cases to only serve a subset of packages, one such case is internal lab environment with 
limited storage. To archive only a subset of the registry:

```julia
# assume that I'm only interested in hosting packages for these
developers_or_packages = Any[
    r"/Julia\w*/", # all Julia* orgs
    "timholy",
    "invenia",
    "MacroTools.jl"
]

pkgs = read_packages(registry) do pkg
    any(developers_or_packages) do x
        occursin(x, pkg.url)
    end
end

# explicitly specify packages you want to host
make_tarball(registry; packages=pkgs)
```

Note that the current implementation of Pkg doesn't support multiple pkg server, which means if you
only host a subset of packages, those you don't host can only be downloaded from the original 
fallback github/aws servers.
