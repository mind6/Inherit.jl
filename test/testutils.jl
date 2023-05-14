
module m123
module m1234
module m12345
module m123456
	using Inherit, Test
	struct S end

	@testset "nested modules" begin
		@test Inherit.tostring(fullname(parentmodule(S)), nameof(S)) == "Main.m123.m1234.m12345.m123456.S"
		# @test Inherit.getmodule(@__MODULE__, fullname(@__MODULE__)) == @__MODULE__
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
		[:( function f(x::Fruit) end), :( function f(x::M2.Orange) end)],
		[:( function f(x::M1.Fruit) end),  :( function f(x::M2.Orange) end)],
		[:( function f(x::M1.M1.Fruit) end),  :( function f(x::M2.Orange) end)],
		[:( function f(x::Main.M1.M1.Fruit) end),  :( function f(x::M2.Orange) end)],

		### if any qualifier does not match the basemodule, we no longer know what object this is so we don't reduce it 
		[:( function f(x::M1.M2.Fruit) end),  :( function f(x::M1.M2.Fruit) end)],
		[:( function f(x::M2.M1.Fruit) end),  :( function f(x::M2.M1.Fruit) end)],
		[:( function f(x::M1.M99.Fruit) end),  :( function f(x::M1.M99.Fruit) end)],
		[:( function f(x::M99.M1.Fruit) end),  :( function f(x::M99.M1.Fruit) end)],
		[:( function f(x::M99.Main.M1.Fruit) end),  :( function f(x::M99.Main.M1.Fruit) end)],
		[:( function f(x::Main.Fruit) end),  :( function f(x::Main.Fruit) end)],

		### reductions work even when used as type parameters
		[:( function f(x::Pair{Fruit, Int}) end), :( function f(x::Pair{M2.Orange,Int}) end)],
		[:( function f(x::Pair{<:Fruit, Int}) end), :( function f(x::Pair{<:M2.Orange, Int}) end)],
		[:( function f(x::Pair{<:Main.M1.Fruit, Int}) end), :( function f(x::Pair{<:M2.Orange, Int}) end)],
		[:( function f(::Int, x::Vector{<:Pair{<:M1.M1.M1.Fruit, Int}}, dummy2) end), 
			:( function f(::Int, x::Vector{<:Pair{<:M2.Orange, Int}}, dummy2) end)],
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
