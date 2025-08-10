using Test, Inherit
if !haskey(ENV, "JULIA_DEBUG")
	ENV["JULIA_DEBUG"] = "Inherit"
end
if VERSION.minor >= 11
	import REPL
end

"
Basic interface definition test. Interfaces can be redefined replacing existing definition. They are verified on module __init__(). 

Dispatch tests ensure the reduced signature evaluation step is not overwriting method defintions.
"
module M1
	using Inherit, Test
	export Fruit 

	"base types can be documented"
	@abstractbase struct NoSubTypesOK impliedAnyOK end

	"second base type"
	@abstractbase struct Fruit
		weight::Float32
		function cost_old(fruit::M1.M1.M1.Fruit, unitprice::Float32)::Float32 end
	end

	### should show a warning message, indicating we're going to reset data for the type
	"third base type"
	@abstractbase struct Fruit
		weight::Float32
		"a useful function"
		function cost(fruit::M1.Fruit, unitprice::Float32)::Float32 end
	end
	
	"derived types can also be documented"
	@implement struct Orange <: M1.Fruit end
	@implement struct Kiwi <: Fruit end
	@implement struct Apple <: Fruit 
		coresize::Int 
	end
	"has more than"
	function cost(fruit::Union{Orange, Kiwi}, unitprice::Number)
		unitprice * fruit.weight
	end
	"one part"
	function cost(apple::Apple, unitprice::Float32)
		unitprice * (apple.weight + apple.coresize) 
	end

	@verify_interfaces
	
	"""
	declarations are evaluated at compile time for their function signatures, this leaves behind empty functions in the module which are not cleaned up until runtime. If the method dispatch test is run at compile time it will fail with an ambiguous call error.
	"""
	function runtime_test()
		@testset "basic field inheritance" begin 
			@test_throws ArgumentError fieldnames(Fruit)		#interfaces are abstract types
			@test fieldnames(Orange) == fieldnames(Kiwi) == (:weight,)
			@test fieldnames(Apple) == (:weight, :coresize)
		end

		@testset "method dispatch from abstractbase" begin
			basket = Fruit[Orange(1), Kiwi(2.0), Apple(3,4)]
			@test [cost(item, 2.0f0) for item in basket] == [2.0f0, 4.0f0, 14.0f0]
		end

		@testset "method comments no longer requires __init__" begin
			@test strip(string(@doc(NoSubTypesOK))) == "base types can be documented"
			@test strip(string(@doc(Fruit))) == "third base type"
			@test strip(string(@doc(Orange))) == "derived types can also be documented"

			@test replace(string(@doc M1.cost), "\n"=>"") == "a useful functionhas more thanone part"
		end
	end
end

M1.runtime_test()

#test that we can evaluate an expression in a shadow module, and get the signature as if it was evaluated in the parent module. This allows us to keep the parent module free of prototype functions, which can cause ambiguities.
@testset "test createshadowmodule" begin
	line = :(function testfunc(fruit::M1.Fruit, unitprice::Float32)::Float32 end)
	m1func = Core.eval(M1, :(function testfunc end))
	m1method = Core.eval(M1, line)

	# the functype is tied to the module, so we need to get it from the base module
	m1functype = typeof(m1func) 
	@test m1functype === typeof(m1func)
	@test m1functype isa DataType

	origsig = Inherit.last_method_def(m1func).sig

	Mshadow = Inherit.createshadowmodule(M1)
	shadowsig = Inherit.make_function_signature(M1, Mshadow, m1functype, line)

	@test origsig == shadowsig
	@test isdefined(M1, :TestSetException)
	@test !isdefined(Mshadow, :TestSetException)

	Inherit.import_symbol_into_shadowmodule(M1, Mshadow, :TestSetException)
	@test isdefined(Mshadow, :TestSetException)

	Inherit.cleanup_shadowmodule(Mshadow)
end



# :(struct Fruit<:B
# 	weight::Float32
# 	"a useful function"

# 	function cost(fruit::M1.Fruit, unitprice::Float32)::Float32 end
# end) |> dump

"
Cross module inheritance with name clash resolution
"
module M2
	using Inherit, Test
	import Main.M1

	@abstractbase struct Fruit
		weight2::Float32
		function cost(fruit::Fruit, unitprice::Float32)::Float32 end
	end

	@implement struct Orange <: Fruit end
	@implement struct Orange1 <: Main.M1.Fruit end
	function cost(item::Orange, unitprice::Number)
		item.weight2 * unitprice
	end
	function M1.cost(item::Orange1, unitprice::Number)
		item.weight * unitprice
	end
	@verify_interfaces
	@testset "implement @abstractbase from another module" begin
		@test fieldnames(Orange) == (:weight2,)
		@test fieldnames(Orange1) == (:weight,)
	end
end

@testset "find_supertype_module" begin
	# Test for cross-module supertype
	@test Inherit.find_supertype_module(M2.Orange1, Inherit.TypeIdentifier(((:Main, :M1), :Fruit))) === M1

	# Test for same-module supertype
	@test Inherit.find_supertype_module(M2.Orange, Inherit.TypeIdentifier(((:Main, :M2), :Fruit))) === M2
	@test Inherit.find_supertype_module(M1.Orange, Inherit.TypeIdentifier(((:Main, :M1), :Fruit))) === M1

	# Test for type that is not a subtype of the specified supertype
	@test_throws ErrorException Inherit.find_supertype_module(M2.Orange, Inherit.TypeIdentifier(((:Main, :M1), :Fruit)))

	# Test error path when supertype is not found
	@test_throws "requested identS Main.M3.Fruit is not a supertype of discovered runtime type Main.M1.Fruit" Inherit.find_supertype_module(M2.Orange1, Inherit.TypeIdentifier(((:Main, :M3), :Fruit)))
end

@testset "additional M1 and M2 tests" begin
	# Test field inheritance in M1
	@testset "M1 field inheritance" begin
		 orange = M1.Orange(1.5f0)
		 kiwi = M1.Kiwi(0.8f0)
		 apple = M1.Apple(2.0f0, 3)
		 
		 @test orange.weight ≈ 1.5f0
		 @test kiwi.weight ≈ 0.8f0
		 @test apple.weight ≈ 2.0f0
		 @test apple.coresize == 3
	end

	# Test method dispatch in M1
	@testset "M1 method dispatch" begin
		 orange = M1.Orange(1.5f0)
		 kiwi = M1.Kiwi(0.8f0)
		 apple = M1.Apple(2.0f0, 3)
		 
		 @test M1.cost(orange, 2.0f0) ≈ 3.0f0
		 @test M1.cost(kiwi, 3.0f0) ≈ 2.4f0
		 @test M1.cost(apple, 1.5f0) ≈ (2.0f0 + 3) * 1.5f0
	end

	# Test cross-module field inheritance
	@testset "M2 field inheritance" begin
		 orange = M2.Orange(1.2f0)
		 orange1 = M2.Orange1(0.9f0)
		 
		 @test orange.weight2 ≈ 1.2f0
		 @test orange1.weight ≈ 0.9f0
	end

	# Test cross-module method dispatch
	@testset "M2 method dispatch" begin
		 orange = M2.Orange(1.2f0)
		 orange1 = M2.Orange1(0.9f0)
		 
		 @test M2.cost(orange, 2.0f0) ≈ 2.4f0
		 @test M1.cost(orange1, 2.0f0) ≈ 1.8f0
	end

	# Test type relationships
	@testset "Type relationships" begin
		 @test M1.Orange <: M1.Fruit
		 @test M2.Orange <: M2.Fruit
		 @test M2.Orange1 <: M1.Fruit
		 @test !(M2.Orange <: M1.Fruit)
	end
end

"
@implement only, no use of @abstractbase
"
module M3
	using Inherit, Test, ..M1
	import ..M1: cost
	export Apple, Fruit, cost

	@implement struct Apple <: Fruit end
	
	function cost(item::Apple, unitprice::Number)
		item.weight * unitprice
	end
	
	@verify_interfaces

	@testset "implement only; auto imported function" begin
		#since M3 contains `using M1`, its cost function is identical to that of M1
		@test all(isequal.(methods(M1.cost), methods(M3.cost)))		 

		@test parentmodule(cost) == M1
	end

end


module M3client
	using ..M3, Test
	import ..M1: cost
	@testset "client syntax test" begin
		item = Apple(1.5)
		@test item isa Fruit
		@test cost(item, 5.0) == 7.5
	end
end

"
multilevel inheritance
"
module M4
	using Inherit, Test, ..M1
	import ..M1: cost
	export Berry

	@abstractbase struct Berry <: M1.Fruit
		cluster::Int
		function bunchcost(b::Berry)::Float32 end
	end

	### this is an important test for whether @abstractbase above is importing M1.cost
	function cost(item::M4.Berry, unitprice::Float32)
		unitprice * (item.weight + item.cluster) 
	end	

	@implement struct BlueBerry <: Berry end
	function bunchcost(item::BlueBerry) 	
		return 1.5 
	end

	function cost(item::BlueBerry, unitprice::Number)
		item.weight * unitprice + item.cluster * bunchcost(item) 	
	end

	@verify_interfaces
	@testset "multilevel inheritance" begin
		#since M4 contains `using M1`, its cost function is identical to that of M1
		@test all(isequal.(methods(M1.cost), methods(M4.cost)))		 
		
		#but bunchcost was introduced only in M4
		@test rand(methods(bunchcost)).module == M4

		@test cost(BlueBerry(1.0, 3), 1.0) == 5.5
		# Inherit.setreportlevel(@__MODULE__, ThrowError)
		# @test_nothrows __init__()
	end

end

@testset "function M1.cost exists (due to auto import)\nbut no methods for required signature" begin
	try
		eval(:(
			module M4fail
				using Inherit, Test, ..M1
				@abstractbase struct Berry <: M1.Fruit
					cluster::Int
					function bunchcost(b::Berry, unitprice::Float32)::Float32 end
				end
				
				@implement struct BlueBerry <: Berry end
				bunchcost(item::BlueBerry, ::Float32) = 1.0

				Inherit.reportlevel = ThrowError
				@verify_interfaces
			end
		))
		@test false
	catch e
		@test e isa LoadError 
		if !(e.error isa ImplementError)
			throw(e.error)
		end
		@test contains(e.error.msg, "Subtype Main.M4fail.BlueBerry must satisfy Tuple{typeof(Main.M1.cost), Main.M4fail.BlueBerry, Float32}")
		# println(e.error.msg)
	end
end

@testset "no methods at all for punchcost" begin
	try
		eval(:(
			module M4fail2
				using Inherit, Test, ..M1

				@abstractbase struct Berry <: M1.Fruit
					cluster::Int
					function punchcost(b::Berry, unitprice::Float32)::Float32 end
				end
				M1.cost(item::Fruit, ::Float32) = 1.0
				
				@implement struct BlueBerry <: Berry end

				Inherit.reportlevel = ThrowError
				@verify_interfaces
			end
		))
		@test false
	catch e
		@test e isa LoadError 
		@test e.error isa ImplementError
		@test contains(e.error.msg, "No methods defined for `M4fail2.punchcost`")
		# println(e.error.msg)
	end
end

"
3 levels of inheritance from a 3rd module
"
module M4client
	using Inherit, Test, ..M4
	import ..M4: cost, bunchcost
	@implement struct BlueBerry <: Berry end
	function bunchcost(item::BlueBerry) 3.33 end
	function cost(item::BlueBerry, unitprice::Float32) 6.66 end		#this only works from REPL because there is a toplevel Main. From a package there would very hard to import M1.cost correctly, and it's too untransparent what's being imported.

	@verify_interfaces
	@testset "3 levels and 3 modules satisfied" begin
		@test bunchcost(BlueBerry(1.0, 3)) == 3.33
	end
end

@testset "no methods for required signature of bunchcost" begin
	try
		eval(:(
			module M4clientfail
				using Inherit, Test, ..M4
				@implement struct BlueBerry <: M4.Berry end
				@verify_interfaces
			end
		))
		@test false
	catch e
		@test e isa LoadError 
		@test e.error isa ImplementError
		@test contains(e.error.msg, "Subtype Main.M4clientfail.BlueBerry must satisfy Tuple{typeof(Main.M4.bunchcost), Main.M4clientfail.BlueBerry}")
		# println(e.error.msg)
	end
end

"@abstractbase only - check interface doc"
module M5
	using Inherit, Test

	@abstractbase struct Fruit
		weight::Float64
		"comments from declarations are at the front of method comments"
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	"this implementation satisfies the interface declaration for all subtypes of Fruit"
	function cost(item::Fruit, unitprice::Real)
		unitprice * item.weight
	end		

	@testset "doc check - @abstractbase only" begin
		@test replace(string(@doc(cost)), r"(\n)+"=>".") == "comments from declarations are at the front of method comments.this implementation satisfies the interface declaration for all subtypes of Fruit."
	end
end

"@abstractbase only - check interface doc with empty method table"
module M5b
	using Inherit, Test

	@abstractbase struct Fruit
		weight::Float64
		"comments from declarations are at the front of method comments"
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	
	@testset "doc check - empty method table" begin
		@test replace(string(@doc(cost)), r"(\n)+"=>".") == "comments from declarations are at the front of method comments."
	end
end

"
- mutability must match with base types
- put implementation in abstract base to allow extensibility
"
module M6
	using Inherit, Test, ..M1
	@abstractbase mutable struct Fruit <: Any
		weight
		const seller
	end
	
	@implement mutable struct Apple <: Fruit end

	@abstractbase struct Berry end

	@verify_interfaces

	@testset "mutability tests" begin	
		@test_throws "mutability" @implement struct Apple <: Fruit end
		@test_throws "mutability" @implement mutable struct Cherry <: Berry end
		@test_throws "Any is not a valid type for implementation by BlackBerry" @implement mutable struct BlackBerry <: Any end

		apple = Apple(1.0, "washington")
		apple.weight = 2.0
		@test_throws "const field" apple.seller = "california"
		@test apple.weight == 2.0
	end
end

module M7
	export MyType, MyType2
	struct MyType end
	struct MyType2 end
end
module M7client
	using ..M7
	using Inherit, Test
	@abstractbase struct T 
		function somefunc(a::MyType, b::MyType2) end
	end
	@testset "importing using'ed symbols into shadowmodule" begin
		@test isdefined(M7client, :MyType)
		@test isdefined(M7client, :MyType2)
		shadowmod = Base.invokelatest(getproperty, M7client, Inherit.H_SHADOW_SUBMODULE)
		@test isdefined(shadowmod, :MyType)
		@test isdefined(shadowmod, :MyType2)
	end
end

module M80
	using Inherit, Test
	@verify_interfaces
	@testset "verify_interfaces with no types defined" begin
		@test true
	end
end


@testset "parametric argument types must be matched exactly" begin
	try
		eval(:(
			module M9fail
				using Inherit, Test
				import ..M1
			
				@abstractbase struct Berry <: M1.Fruit
					"the supertype can appear in a variety of positions"
					function pack(time::Int, bunch::Dict{String, <:AbstractVector{Berry}}) end
				end
			
				@implement struct BlueBerry <: Berry end
			
				"the implementing method's argument types can be broader than the interface's argument types"
				function pack(time::Number, bunch::Dict{String, <:AbstractVector{BlueBerry}}) 
					println("packing things worth \$$(cost(first(values(bunch))[1], 1.5))")
				end

				@verify_interfaces
			end		
		))
		@test false
	catch e
		@test e isa LoadError 
		@test e.error isa ImplementError
		@test contains(e.error.msg, "Subtype Main.M9fail.BlueBerry must satisfy Tuple{typeof(Main.M9fail.pack), Int64, Dict{String, <:AbstractVector{Main.M9fail.Berry}}}")
		# println(e.error.msg)
	end
end

module M11
	using Inherit, Test

	struct T1 <: AbstractVector{Int} end
	# @abstractbase struct T1 <: AbstractVector{Int} end

	@testset "not implemented" begin
		@test_throws "it was not declared with @abstractbase" @implement struct T3{P} <: T1 end
	end

end

