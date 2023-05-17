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
	
	@testset "basic field inheritance" begin 
		@test_throws ArgumentError fieldnames(Fruit)		#interfaces are abstract types
		@test fieldnames(Orange) == fieldnames(Kiwi) == (:weight,)
		@test fieldnames(Apple) == (:weight, :coresize)
	end

	@testset "method dispatch from abstractbase" begin
		basket = Fruit[Orange(1), Kiwi(2.0), Apple(3,4)]
		@test [cost(item, 2.0f0) for item in basket] == [2.0f0, 4.0f0, 14.0f0]
	end

	@testset "method comments require __init__" begin
		@test strip(string(@doc(NoSubTypesOK))) == "base types can be documented"
		@test strip(string(@doc(Fruit))) == "third base type"
		@test strip(string(@doc(Orange))) == "derived types can also be documented"

		@test_nothrows __init__()
		#NOTE: unfortunately, the method declaration comment will be last one in the module
		@test replace(string(@doc M1.cost), "\n"=>"") == "has more thanone parta useful function"
	end
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

	@testset "definition errors" begin
		@test_throws "duplicate method definition" @abstractbase struct Fruit
			weight::Float32
			function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
			function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
		end
	end

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
	@testset "implement @abstractbase from another module" begin
		@test fieldnames(Orange) == (:weight2,)
		@test fieldnames(Orange1) == (:weight,)

		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_nothrows M2.__init__()
		@test_throws SettingsError Inherit.setreportlevel(@__MODULE__, SkipInitCheck)
	end
	# Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"
@implement only, no use of @abstractbase
"
module M3
	using Inherit, Test, ..M1
	export Apple, Fruit, cost

	@implement struct Apple <: Fruit end
	
	function cost(item::Apple, unitprice::Number)
		item.weight * unitprice
	end
	
	@postinit function __myinit1__()
		@info "first post init for $(@__MODULE__)"
	end

	@postinit function __myinit2__()
		@info "second post init for $(@__MODULE__)"
	end

	@testset "implement only; auto imported function" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test parentmodule(cost) == M1
		@test_nothrows __init__()
	end

end

module M3client
	using ..M3, Test
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
	export Berry
	Inherit.setreportlevel(@__MODULE__, SkipInitCheck)

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

	@testset "multilevel inheritance" begin
		@test methods(cost)[1].module == M1
		@test methods(bunchcost)[1].module == M4
		@test cost(BlueBerry(1.0, 3), 1.0) == 5.5
		# Inherit.setreportlevel(@__MODULE__, ThrowError)
		# @test_nothrows __init__()
	end

end

module M4fail
	using Inherit, Test, ..M1
	@abstractbase struct Berry <: M1.Fruit
		cluster::Int
		function bunchcost(b::Berry, unitprice::Float32)::Float32 end
	end
	
	@implement struct BlueBerry <: Berry end
	bunchcost(item::BlueBerry, ::Float32) = 1.0

	@testset "multilevel inheritance" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_throws ImplementError __init__()
	end

	Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"
Tests that satisfying all subtypes doesn't incorrectly skip a later declaration
"
module M4fail2
	using Inherit, Test, ..M1
	@abstractbase struct Berry <: M1.Fruit
		cluster::Int
		function punchcost(b::Berry, unitprice::Float32)::Float32 end
	end
	cost(item::Fruit, ::Float32) = 1.0
	
	@implement struct BlueBerry <: Berry end

	@testset "multilevel inheritance" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_throws ImplementError __init__()
	end

	Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"
multilevel inheritance from a 3rd module
"
module M4client
	using Inherit, Test, ..M4
	@implement struct BlueBerry <: Berry end
	function bunchcost(item::BlueBerry) 1.0 end


	@testset "3 levels and 3 modules satisfied" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_nothrows __init__()
	end
end

module M4clientfail
	using Inherit, Test, ..M4
	@implement struct BlueBerry <: M4.Berry end

	@testset "3 levels and 3 modules not satisfied" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_throws ImplementError __init__()
	end
	Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"@abstractbase only - check interface doc"
module M5
	using Inherit, Test

	@abstractbase struct Fruit
		weight::Float64
		"comments from declarations are appended at the end of method comments"
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	"this implementation satisfies the interface declaration for all subtypes of Fruit"
	function cost(item::Fruit, unitprice::Real)
		unitprice * item.weight
	end		

	@postinit function myinit()
		@testset "doc check - @abstractbase only" begin
			@test replace(string(@doc(cost)), r"\s"=>"") == replace(
			"this implementation satisfies the interface declaration for all subtypes of Fruit"* "comments from declarations are appended at the end of method comments", r"\s"=>"")
		end
	end	
end

"@abstractbase only - check interface doc with empty method table"
module M5b
	using Inherit, Test

	@abstractbase struct Fruit
		weight::Float64
		"comments from declarations are appended at the end of method comments"
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	
	@postinit function myinit()
		@testset "doc check - empty method table" begin
			@test replace(string(@doc(cost)), r"\s"=>"") == replace("comments from declarations are appended at the end of method comments", r"\s"=>"")
		end
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

begin

"post init by itself"
module M7
	using Inherit
	# @abstractbase struct S end
	initialized::Bool = false
	@postinit () -> begin
		M7.initialized = true
	end
end

@testset "postinit by itself" begin
	@test M7.initialized == true
end

"silently ovewriting Inherit.jl's __init__()"
module M8
	using Inherit, ..M1
	@implement struct Coconut <: Fruit  end
	initialized::Bool = false
	function __init__()
		M8.initialized = true
	end
end

@testset "__init__ gets silently overwritten" begin
	@test M8.initialized == true
end

end


module doctest1
module M1
	using Inherit

	@abstractbase struct Fruit
		weight::Float64
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	function cost(item::Fruit, unitprice::Number)
		unitprice * item.weight
	end		
end

module M2
	using Inherit
	import ..M1

	@abstractbase struct Berry <: M1.Fruit
		function pack(time::Int, bunch::Dict{String, AbstractVector{<:Berry}})::Float32 end
	end

	@implement struct BlueBerry <: Berry end
	function pack(time::Number, bunch::Dict{String, AbstractVector{<:BlueBerry}})::Float32 end

end
end