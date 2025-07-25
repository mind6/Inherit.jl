@show @__DIR__
cd(joinpath(@__DIR__, ".."))
@show pwd()

using Pkg
Pkg.activate(".")

begin
	@time import PackageExtensionsExample
	@time import Inherit
	@time import PkgTest4
end

# TODO: now we want to make Inherit's __init__() function as simple as possible, all it doess is register itself with the Inherit.jl module. We have to ensure verification will be compiled like fn_greet().