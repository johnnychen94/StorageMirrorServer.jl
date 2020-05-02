# StorageServer

[![Build Status](https://travis-ci.com/johnnychen94/StorageServer.jl.svg?branch=master)](https://travis-ci.com/johnnychen94/StorageServer.jl)
[![Codecov](https://codecov.io/gh/johnnychen94/StorageServer.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/johnnychen94/StorageServer.jl)

This package is used to set up a Julia Package Storage Server. The protocol details are
described in https://github.com/JuliaLang/Pkg.jl/issues/1377.

TL;DR; A storage server contains all the static contents you need to download when you do `]add PackageName`.

To set up a storage server, you'll need to:

1. get/update the static contents
2. serve them as a HTTP(s) service using nginx or whatever you like

This package is written to make step 1 easy and stupid.

# Mirror

See the [example script](examples/gen_static_full.example.jl) for how to build the data from scratch.

```julia
upstreams = ["pkg.julialang.org"]
mirror_tarball("General", upstreams; static_dir = STATIC_DIR, clones_dir = CLONES_DIR)
```

# Build from scratch

Similar to mirror, you only need to change the `mirror_tarball` part to `make_tarball`.

```julia
make_tarball("General"; static_dir = STATIC_DIR, clones_dir = CLONES_DIR)
```

# Serve only a subset

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
