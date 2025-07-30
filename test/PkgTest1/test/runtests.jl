cd(joinpath(@__DIR__, ".."))
@show pwd()

# ENV["JULIA_DEBUG"] = "Inherit"
ENV["JULIA_DEBUG"] = nothing
using Pkg
Pkg.activate(".")
Pkg.resolve()

using Distributed

pids = addprocs(1)
import Inherit: warmup_import_package
rmprocs(pids)

warmup_import_package(:PkgTest1)


t = @timed using PkgTest1 # should take 4ms in precompiledsame session, 1.5ms in new session

using Test
@testset "loading performance" begin
	@info "loaded PkgTest1 in $(t.time) seconds"
	@test t.time < 0.0025	# normal times are 1.5ms in julia 1.11, 1.8ms in Julia 1.10 LTS

	if Int(VERSION.minor) >= 11
		@test t.recompile_time == 0	# requires Julia 1.11
		@test t.compile_time == 0
	end
end


@testset "basic field inheritance" begin 
	@test_throws ArgumentError fieldnames(Fruit)		#interfaces are abstract types
	@test fieldnames(Orange) == fieldnames(Kiwi) == (:weight,)
	@test fieldnames(Apple) == (:weight, :coresize)
end

@testset "method dispatch from abstractbase" begin
	basket = Fruit[Orange(1), Kiwi(2.0), Apple(3,4)]
	@test [cost(item, 2.0f0) for item in basket] == [2.0f0, 4.0f0, 14.0f0]
end

# string conversions fails in 1.11 if run before REPL is ready
if Int(VERSION.minor) >= 11
	using REPL
end
@testset "method comments work with compile time only evaluation" begin
	
	@test strip(string(@doc(NoSubTypesOK))) == "base types can be documented"
	@test strip(string(@doc(Fruit))) == "third base type"
	@test strip(string(@doc(Orange))) == "derived types can also be documented"
	
	#NOTE: unfortunately, the method declaration comment will be appended last to the docstring
	@test replace(string(@doc PkgTest1.cost), "\n"=>"") == "a useful functionhas more thanone part"
end