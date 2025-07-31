cd(joinpath(@__DIR__, ".."))
@show pwd()

# ENV["JULIA_DEBUG"] = "Inherit"
ENV["JULIA_DEBUG"] = nothing
using Pkg
Pkg.activate(".")
Pkg.develop(path=joinpath(@__DIR__, "..", "..","PkgTest2"))

using PkgTest3

