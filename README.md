# StorageMirrorServer

[![Unit Test][action-img]][action-url]
[![PkgEval][pkgeval-img]][pkgeval-url]
[![Codecov][codecov-img]][codecov-url]
![status][pkg-status]

This package is used to set up a Julia Package Storage Server for mirror sites. The protocol details are
described in https://github.com/JuliaLang/Pkg.jl/issues/1377.

TL;DR; A storage server contains all the static contents you need to download when you do `]add PackageName`.

If you just want a cache layer service, [PkgServer.jl](https://github.com/JuliaPackaging/PkgServer.jl) is a
better choice. This package is made to _permanently_ keep the static contents.

To set up a storage server, you'll need to:

1. get/update the static contents
2. serve them as a HTTP(s) service using nginx or whatever you like

This package is written to make step 1 easy and stupid.

## Basic Usage

1. add this package `]add https://github.com/johnnychen94/StorageServer.jl#v0.1.1-rc4`
2. modify the [example script](examples/gen_static_full.example.jl) and save it as `gen_static.jl`
3. pull/build data `julia gen_static.jl`

You can read the not-so-friendly docstrings for advanced usage, but here are something you may want:

* Redirect output `julia gen_static.jl > log.txt 2>&1`
* Utilize multiple threads, set environment variable `JULIA_NUM_THREADS`. For example,
  `JULIA_NUM_THREADS=8 julia gen_static.jl` would use 8 threads to pull data.

## Examples

This package is used to build the [BFSU](https://mirrors.bfsu.edu.cn/help/julia/) mirror site.

## Acknowledgement

This package is modified from the original implementation [gen_static.jl](https://github.com/JuliaPackaging/PkgServer.jl/blob/2614c7d4d7fd8d422d0a82ffe5083a834be56bf8/bin/gen_static.jl).

<!-- badges -->

[action-img]: https://github.com/johnnychen94/StorageMirrorServer.jl/workflows/Unit%20test/badge.svg
[action-url]: https://github.com/johnnychen94/StorageMirrorServer.jl/actions

[pkgeval-img]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/S/StorageMirrorServer.svg
[pkgeval-url]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html

[codecov-img]: https://codecov.io/gh/johnnychen94/StorageMirrorServer.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/johnnychen94/StorageMirrorServer.jl

[pkg-status][https://img.shields.io/badge/status-experimental-red]
