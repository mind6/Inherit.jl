"
# Useful snippets

	ex = MacroTools.prewalk(MacroTools.rmlines, ex)  #NOTE: could break code such as generating module init. Use only for debugging purposes
	ex |> dump

# Testing notes
- throwing exceptions from macros won't be caught. Use `return :(throw(...))` to have the exception evaluate at the caller.
- @test_warn doesn't work on macros
"

using MacroTools, Test, Documenter
using Inherit

### The choice of debug level for Inherit controls will module __init__ will throw exceptions (high log state than debug) or print error messages only (Debug log level)
# ENV["JULIA_DEBUG"] = nothing
ENV["JULIA_DEBUG"] = "Inherit"
ENV[Inherit.E_SUMMARY_LEVEL] = "info"
# delete!(ENV,Inherit.E_SUMMARY_LEVEL)

include("testutils.jl")
include("testmain.jl")


@testset "package loading" begin
	import Pkg
	savedproj = dirname(Pkg.project().path)
	# Pkg.offline(true)
	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest1"))
	using PkgTest1
	PkgTest1.run()
	PkgTest1.greet()

	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest2"))
	using PkgTest2

	begin
		newmod = Inherit.createshadowmodule(PkgTest1)
		Base.eval(newmod, :(	function cost(fruit::PkgTest1.Fruit, unitprice::Float32)::Float32 end ))
		s1=methods(newmod.cost)[1].sig
	end
	
	Pkg.activate(savedproj)
end

doctest(Inherit)


# include("testtraits.jl")