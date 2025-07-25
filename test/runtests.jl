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
ENV["JULIA_DEBUG"] = nothing
# ENV["JULIA_DEBUG"] = "Inherit"
ENV[Inherit.E_SUMMARY_LEVEL] = "info"
# delete!(ENV,Inherit.E_SUMMARY_LEVEL)

#FIXME: Julia 1.10 no longer allows deleting the function prototype during precompilation. (It's necessary to evaluate the prototype expression in the module in which it appears, in order to get the correct types for the function parameters.) Our solution is to leave prototype defined, but detect when its body is empty, indicating there isn't any user implementation of the prototype.



#TODO: error out when overwriting a previous defined module __init__. Note that this won't prevent the user from overwriting Inherit.jl's __init__, but it's still helpful in reducing errors.
include("testutils.jl")
include("testpublicutils.jl")
include("testmain.jl")
include("testparametricstructs.jl")

@testset "package loading" begin
	import Pkg
	savedproj = dirname(Pkg.project().path)
	# Pkg.offline(true)
	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest1"))
	Pkg.resolve()			#this updates manifest.toml so changes such as extensions are available
	using PkgTest1 		#cannot use @test_logs with this statement because it won't be at top level
	modentry = Inherit.getmoduleentry(PkgTest1)
	@test length(modentry.postinit) == 1	#this makes sure the system knows about postinit and will run it

	PkgTest1.run()
	PkgTest1.greet()

	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest2"))
	Pkg.resolve()
	using PkgTest2
	PkgTest2.run()
	
	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest3"))
	Pkg.resolve()
	@test_throws "InterfaceError: method definition duplicates a previous definition:" using PkgTest3

	Pkg.activate(savedproj)
end

doctest(Inherit)


# include("testtraits.jl")