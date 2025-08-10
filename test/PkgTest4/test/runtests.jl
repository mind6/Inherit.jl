@show @__DIR__
cd(joinpath(@__DIR__, ".."))
@show pwd()

using Pkg
Pkg.activate(".")
if VERSION.minor < 11
	Pkg.develop(path="../..")
end
Pkg.resolve()
begin
	# @time import PackageExtensionsExample
	@time import Inherit
	@time import PkgTest4
end
begin
	import PkgTest4
	@time PkgTest4.@greet	#prints "Hello macro! (not precompiling)" because it's being compiled as a script statement
end

# TODO: now we want to make Inherit's __init__() function as simple as possible, all it does is register itself with the Inherit.jl module. We have to ensure verification will be compiled like fn_greet().

H_COMPILETIMEINFO::Symbol = :__Inherit_jl_COMPILETIMEINFO
quote
	global $H_COMPILETIMEINFO = CompiletimeModuleInfo()
end