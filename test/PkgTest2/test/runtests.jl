cd(joinpath(@__DIR__, ".."))
@show pwd()

# ENV["JULIA_DEBUG"] = "Inherit"
ENV["JULIA_DEBUG"] = nothing
using Pkg
Pkg.activate(".")
Pkg.develop(path=joinpath(@__DIR__, "..", "..","PkgTest1"))

using PkgTest2
PkgTest2.test()

