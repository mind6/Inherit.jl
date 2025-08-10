cd(joinpath(@__DIR__, ".."))
@show pwd()

# ENV["JULIA_DEBUG"] = "Inherit"
ENV["JULIA_DEBUG"] = nothing
using Pkg
Pkg.activate(".")
Pkg.develop(path="../PkgTest2")
Pkg.develop(path="../..")


using PkgTest3

@assert PkgTest3.Inherit === PkgTest3.PkgTest2.Inherit
PkgTest3.test()