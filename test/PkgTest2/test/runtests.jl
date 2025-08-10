cd(joinpath(@__DIR__, ".."))
@show pwd()

# ENV["JULIA_DEBUG"] = "Inherit"
ENV["JULIA_DEBUG"] = nothing
using Pkg
Pkg.activate(".")

if VERSION.minor < 11
	Pkg.develop(path="../PkgTest1")
	Pkg.develop(path="../..")
end

using PkgTest2
@assert PkgTest2.Inherit === PkgTest2.PkgTest1.Inherit

PkgTest2.test()

