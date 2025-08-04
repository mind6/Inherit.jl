cd(@__DIR__)
using Pkg
Pkg.activate("..")

using MacroTools, Test
using Inherit

ENV["JULIA_DEBUG"] = nothing
# ENV["JULIA_DEBUG"] = "Inherit"


@testset verbose = true "test Inherit.jl" begin
	include("test_constructors.jl")
	include("test_constructors2.jl")
	include("testutils.jl")
	include("testmain.jl")
	include("testparametricstructs.jl")
	include("testpublicutils.jl")

	include("./PkgTest1/test/runtests.jl")
	include("./PkgTest2/test/runtests.jl")
	include("./PkgTest3/test/runtests.jl")

end


# doctest(Inherit)

# include("testtraits.jl")