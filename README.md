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

1. add this package `]add StorageMirrorServer`
2. modify the [example script](examples/gen_static_full.example.jl) and save it as `gen_static.jl`
3. pull/build data `julia gen_static.jl`

You can read the not-so-friendly docstrings for advanced usage, but here are something you may want:

* Redirect output `julia gen_static.jl > log.txt 2>&1`
* Utilize multiple threads, set environment variable `JULIA_NUM_THREADS`. For example,
  `JULIA_NUM_THREADS=8 julia gen_static.jl` would use 8 threads to pull data.

## Environment Variables

There are some environment variables that you can use to help configure the download worker `curl`:

* `BIND_ADDRESS` that passes to `curl --interface $BIND_ADDRESS`, this can be useful when multiple
  network cards are available (newly added in `v0.2.1`)

## Examples

This package is used to power the Julia pkg mirror in the following mirror sites:

* [BFSU] in Beijing Foreign Studies University
* [TUNA] in Tsinghua University
* [SJTUG] in Shanghai Jiao Tong University
* [USTC] in University of Science and Technology of China

## Acknowledgement

The first version of this package is modified from the original implementation [gen_static.jl]. During the development of this package, I get a lot of helps from [Elliot Saba](https://github.com/staticfloat) and [Stefan Karpinski](https://github.com/StefanKarpinski) to understand the Pkg & Storage protocol designs. 
[Chi Zhang](https://github.com/skyzh) from SJTUG has shown his great patience and passion in testing out the rolling versions and given me a lot of feedbacks and suggestions.

<!-- badges -->

[action-img]: https://github.com/johnnychen94/StorageMirrorServer.jl/workflows/Unit%20test/badge.svg
[action-url]: https://github.com/johnnychen94/StorageMirrorServer.jl/actions

[pkgeval-img]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/S/StorageMirrorServer.svg
[pkgeval-url]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/report.html

[codecov-img]: https://codecov.io/gh/johnnychen94/StorageMirrorServer.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/johnnychen94/StorageMirrorServer.jl

[pkg-status]: https://img.shields.io/badge/status-experimental-red

<!-- URLS -->

[BFSU]: https://mirrors.bfsu.edu.cn/help/julia/
[TUNA]: https://mirrors.tuna.tsinghua.edu.cn/help/julia/
[SJTUG]: https://mirrors.sjtug.sjtu.edu.cn/julia/
[USTC]: http://mirrors.ustc.edu.cn/julia
[gen_static.jl]: https://github.com/JuliaPackaging/PkgServer.jl/blob/2614c7d4d7fd8d422d0a82ffe5083a834be56bf8/bin/gen_static.jl
