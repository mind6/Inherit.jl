"
# Useful snippets

	ex = MacroTools.prewalk(MacroTools.rmlines, ex)  #NOTE: could break code such as generating module init. Use only for debugging purposes
	ex |> dump

# Testing notes
- throwing exceptions from macros won't be caught. Use `return :(throw(...))` to have the exception evaluate at the caller.
- @test_warn doesn't work on macros
"

using MacroTools, Test
using Inherit

### The choice of debug level for Inherit controls will module __init__ will throw exceptions (high log state than debug) or print error messages only (Debug log level)
ENV["JULIA_DEBUG"] = nothing
# ENV["JULIA_DEBUG"] = "Inherit"

module m123
module m1234
module m12345
module m123456
	using Inherit, Test
	struct S end

	@testset "nested modules" begin
		@test Inherit.tostring(fullname(parentmodule(S)), nameof(S)) == "Main.m123.m1234.m12345.m123456.S"
		@test Inherit.getmodule(@__MODULE__, fullname(@__MODULE__)) == @__MODULE__
		@test Inherit.to_import_expr(:func, fullname(@__MODULE__)...) == :(import Main.m123.m1234.m12345.m123456:func)

	end
end
end
	Main.m123.m1234.m12345.m123456.S
end
end

@testset "utils tests" begin
	@test Inherit.lastsymbol(:(a)) == :a
	@test Inherit.lastsymbol(:(a.b)) == :b
	@test Inherit.lastsymbol(:(a.b.c.d)) == :d
	@test string(Inherit.to_qualified_expr(:a)) == "a"
	@test string(Inherit.to_qualified_expr(:a, :b))  == "a.b"
	@test string(Inherit.to_qualified_expr(:a, :b, :c))  == "a.b.c"
	@test string(Inherit.to_qualified_expr(:a, :b, :c, :d) ) == "a.b.c.d"

	sig = methods(findmax)[1].sig
	@test Inherit.make_variable_tupletype(@__MODULE__, sig.types...) == sig
	@test Inherit.to_import_expr(:func, :Main) == :(import Main:func)
	@test Inherit.to_import_expr(:func, :Main, :M1) == :(import Main.M1:func)
	@test MacroTools.splitdef(Inherit.privatize_funcname(:( function f(x::Main.M1.M1.Fruit) end)))[:name] == :__f
end

@testset "reduce base type to subtype in interface definition" begin
	testexprs = [
		### basetype and any number of basemodule qualifiers gets reduced to implmodule.impltype
		[:( function f(x::Fruit) end), :( function f(x::Main.M2.Orange) end)],
		[:( function f(x::M1.Fruit) end),  :( function f(x::Main.M2.Orange) end)],
		[:( function f(x::M1.M1.Fruit) end),  :( function f(x::Main.M2.Orange) end)],
		[:( function f(x::Main.M1.M1.Fruit) end),  :( function f(x::Main.M2.Orange) end)],

		### if any qualifier does not match the basemodule, we no longer know what object this is so we don't reduce it 
		[:( function f(x::M1.M2.Fruit) end),  :( function f(x::M1.M2.Fruit) end)],
		[:( function f(x::M2.M1.Fruit) end),  :( function f(x::M2.M1.Fruit) end)],
		[:( function f(x::M1.M99.Fruit) end),  :( function f(x::M1.M99.Fruit) end)],
		[:( function f(x::M99.M1.Fruit) end),  :( function f(x::M99.M1.Fruit) end)],
		[:( function f(x::M99.Main.M1.Fruit) end),  :( function f(x::M99.Main.M1.Fruit) end)],
		[:( function f(x::Main.Fruit) end),  :( function f(x::Main.Fruit) end)],

		### reductions work even when used as type parameters
		[:( function f(x::Pair{Fruit, Int}) end), :( function f(x::Pair{Main.M2.Orange,Int}) end)],
		[:( function f(x::Pair{<:Fruit, Int}) end), :( function f(x::Pair{<:Main.M2.Orange, Int}) end)],
		[:( function f(x::Pair{<:Main.M1.Fruit, Int}) end), :( function f(x::Pair{<:Main.M2.Orange, Int}) end)],
		[:( function f(::Int, x::Vector{<:Pair{<:M1.M1.M1.Fruit, Int}}, dummy2) end), 
			:( function f(::Int, x::Vector{<:Pair{<:Main.M2.Orange, Int}}, dummy2) end)],
	]
	for (expr, expected) in testexprs
		res = Inherit.reducetype(expr, (:Main, :M1), :Fruit, (:Main, :M2), :Orange)
		res = MacroTools.prewalk(MacroTools.rmlines, res)
		expected = MacroTools.prewalk(MacroTools.rmlines, expected)
		# println(res)
		@test res == expected
	end

end
# Inherit.reducetype(:( function f(x::Main.M1.M1.Fruit) end), (:Main, :M1), :Fruit, (:Main, :M2), :Orange) |> dump
# @capture( :( f(x::Fruit) ), f(_::T_ ) )
# @capture( :( f(x::M1.M1.Fruit) ), f(_::m__.T_ ) )
# @capture( :( f(x::Vector{Fruit}) ), f(_::_{T_} ) )
# @capture( :( f(x::Vector{Vector{Fruit}}) ), f(_::_{T_} ) )
# @capture( :( f(x::Vector{<:M1.Fruit}) ), f(_::_{<:m__.T_} ) )
# @capture( :( f(x::Fruit) ), f(_::T_Symbol ) )
# @capture( :( f(x::Fruit) ), f(_::T_Symbol <: S_Symbol ) )
# @capture( :( f(x::Fruit<:Super) ), f(_::T_Symbol <: S_Symbol) )
# @capture( :( f(x::Fruit<:Super) ), f(_::T_Symbol ) )
# begin
# 	macro testmacro(expr)
# 		qn = QuoteNode(expr)
# 		quote 
# 			local ex = $qn
# 			@show ex 
# 		end
# 	end
# 	# @macroexpand @testmacro struct S end
# 	@testmacro struct S end
# end
begin
	
	@capture(:(mutable struct Apple <: Fruit nothing end), 
		(mutable struct T_Symbol <:S_ lines__ end) | (mutable struct T_ lines__ end))
	# @capture(:(struct Apple <:Fruit end), (struct T_ <: S_ end) | (struct T_ lines__ end))
	@show T S 
end
@capture(:(func(x::Int) = 1), (f_(args__) = body_) | (struct S s end))
@show f args

@testset "not implemented" begin
	struct T1 <: AbstractVector{Int} end
	# @abstractbase struct T2 <: AbstractVector{Int} end
	@test_throws ImplementError @implement struct T3{N} <: T1 end
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
	@implement struct Orange1 <: M1.Fruit end
	function cost(item::Orange, unitprice::Number)
		item.weight2 * unitprice
	end
	function Main.M1.cost(item::Orange1, unitprice::Number)
		item.weight * unitprice
	end
	@testset "implement @abstractbase from another module" begin
		@test fieldnames(Orange) == (:weight2,)
		@test fieldnames(Orange1) == (:weight,)

		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_nothrows M2.__init__()
		@test_throws SettingsError Inherit.setreportlevel(@__MODULE__, DisableInit)
	end
	# Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"
@implement only, no use of @abstractbase
"
module M3
	using Inherit, Test, Main.M1
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
		@test parentmodule(cost) == Main.M1
		@test_nothrows __init__()
	end

end

module M3client
	using Main.M3, Test
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
	using Inherit, Test, Main.M1
	export Berry
	Inherit.setreportlevel(@__MODULE__, DisableInit)

	@abstractbase struct Berry <: Main.M1.Fruit
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
		@test methods(cost)[1].module == Main.M1
		@test methods(bunchcost)[1].module == Main.M4
		@test cost(BlueBerry(1.0, 3), 1.0) == 5.5
		# Inherit.setreportlevel(@__MODULE__, ThrowError)
		# @test_nothrows __init__()
	end

end

module M4fail
	using Inherit, Test, Main.M1
	@abstractbase struct Berry <: Main.M1.Fruit
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
multilevel inheritance from a 3rd module
"
module M4client
	using Inherit, Test, Main.M4
	@implement struct BlueBerry <: Berry end
	function bunchcost(item::BlueBerry) 1.0 end


	@testset "3 levels and 3 modules satisfied" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_nothrows __init__()
	end
end

module M4clientfail
	using Inherit, Test, Main.M4
	@implement struct BlueBerry <: M4.Berry end

	@testset "3 levels and 3 modules not satisfied" begin
		Inherit.setreportlevel(@__MODULE__, ThrowError)
		@test_throws ImplementError __init__()
	end
	Inherit.setreportlevel(@__MODULE__, ShowMessage)
end

"
- mutability must match with base types
- put implementation in abstract base to allow extensibility
"
module M6
	using Inherit, Test, Main.M1
	@abstractbase mutable struct Fruit 
		weight
		const seller
	end
	
	@implement mutable struct Apple <: Fruit end

	@abstractbase struct Berry end

	@testset "mutability tests" begin	
		@test_throws "mutability" @implement struct Apple <: Fruit end
		@test_throws "mutability" @implement mutable struct Cherry <: Berry end
		apple = Apple(1.0, "washington")
		apple.weight = 2.0
		@test_throws "const field" apple.seller = "california"
		@test apple.weight == 2.0
	end
end

begin
	import Pkg
	savedproj = dirname(Pkg.project().path)
	# Pkg.offline(true)
	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest1"))
	using PkgTest1
	PkgTest1.run()
	PkgTest1.greet()

	Pkg.activate(joinpath(dirname(@__FILE__), "PkgTest2"))
	using PkgTest2

	Pkg.activate(savedproj)
end

begin
	newmod = Inherit.createshadowmodule(PkgTest1)
	Base.eval(newmod, :(	function cost(fruit::PkgTest1.Fruit, unitprice::Float32)::Float32 end ))
	s1=methods(newmod.cost)[1].sig
end

# include("testtraits.jl")