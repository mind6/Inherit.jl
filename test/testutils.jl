
module m123
module m1234
module m12345
module m123456
	using Inherit, Test
	struct S end

	@testset "nested modules" begin
		@test Inherit.tostring(Inherit.strip_self_reference(fullname(parentmodule(S))), nameof(S)) == "Main.m123.m1234.m12345.m123456.S"
		# @test Inherit.getmodule(@__MODULE__, fullname(@__MODULE__)) == @__MODULE__
	end
end
end
	Main.m123.m1234.m12345.m123456.S
end

module m1235
	module m12356
	end

	using Inherit, Test
	import ..m1234, .m12356, ..m1234.m12345.m123456
	import Main.m123, ....m123.m1234.m12345

	@testset "import expressions" begin
		@test_warn "WARNING: import of " eval(Inherit.to_import_expr(:include, fullname(m1234), fullname(@__MODULE__)))
		@test_warn "WARNING: import of " eval(Inherit.to_import_expr(:include, fullname(m12356), fullname(@__MODULE__)))
		@test_warn "WARNING: import of " eval( Inherit.to_import_expr(:include, fullname(m123456), fullname(@__MODULE__)))

		@test_warn "WARNING: import of " eval( Inherit.to_import_expr(:include, fullname(m123), fullname(@__MODULE__)))
		@test_warn "WARNING: import of " eval( Inherit.to_import_expr(:include, fullname(m12345), fullname(@__MODULE__)))
		@test Inherit.to_import_expr(:cost, (:Main,:Main,:M1), (:Main,:Main,:M2)) == :(import ..M1: cost)
	end
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
	@test MacroTools.splitdef(Inherit.privatize_funcname(:( function f(x::Main.M1.M1.Fruit) end)))[:name] == :__f

end

@testset "reduce base type to subtype in interface definition" begin
	testexprs = [
		### basetype and any number of basemodule qualifiers gets reduced to implmodule.impltype
		[:( function f(x::Fruit) end), :( function f(x::M2.Orange) end)],
		[:( function f(::M1.Fruit) end),  :( function f(::M2.Orange) end)],
		[:( function f(x::M1.M1.Fruit) end),  :( function f(x::M2.Orange) end)],
		[:( function f(x::Main.M1.M1.Fruit) end),  :( function f(x::M2.Orange) end)],

		### if any qualifier does not match the basemodule, we no longer know what object this is so we don't reduce it 
		[:( function f(x::M1.M2.Fruit) end),  :( function f(x::M1.M2.Fruit) end)],
		[:( function f(x::M2.M1.Fruit) end),  :( function f(x::M2.M1.Fruit) end)],
		[:( function f(x::M1.M99.Fruit) end),  :( function f(x::M1.M99.Fruit) end)],
		[:( function f(x::M99.M1.Fruit) end),  :( function f(x::M99.M1.Fruit) end)],
		[:( function f(x::M99.Main.M1.Fruit) end),  :( function f(x::M99.Main.M1.Fruit) end)],
		[:( function f(x::Main.Fruit) end),  :( function f(x::Main.Fruit) end)],

		### parametric types with specific type parameters are ignored
		[:(function f(::Int, x::Vector{Berry}) end), :(function f(::Int, x::Vector{Berry}) end)],
		[:( function f(::Pair{M1.Fruit, Int}) end), :( function f(::Pair{M1.Fruit,Int}) end)],

		### parameters types with range parameters will still be ignored. If a subtype range parameter is allowed, it would be possible to create a container type with the supertype range parameter, which would have no dispatch, despite what the method declaration says.
		[:( function f(x::Pair{<:Fruit, Int}) end), :( function f(x::Pair{<:M2.Orange, Int}) end)],
		[:( function f(::Pair{Float32, <:Main.M1.Fruit}) end), :( function f(::Pair{Float32, <:M2.Orange}) end)],
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

# Inherit.reducetype(:(function f(::Vector{<:M1.Fruit}) end), (:Main, :M1), :Fruit, (:Main, :M2), :Orange)
# @capture( :( f(x::Vector{<:Type{<:Fruit}}) ), f(P_:: A_{<: T_} ) ); @show P A T
# @capture( :( f(x::M1.M1.Fruit) ), f(_::m__.T_ ) )
# @capture( :( f(x::Vector{Fruit}) ), f(_::_{T_} ) )
# @capture( :( f(x::Vector{Vector{Fruit}}) ), f(_::_{T_} ) )
# @capture( :( f(x::Vector{<:M1.Fruit}) ), f(_::_{<:m__.T_} ) )
# @capture( :( f(x::Fruit) ), f(_::T_Symbol ) )
# @capture( :( f(x::Fruit) ), f(_::T_Symbol <: S_Symbol ) )
# @capture( :( <:Fruit), <:T_Symbol )
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
# begin
	
# 	@capture(:(mutable struct Apple <: Fruit nothing end), 
# 		(mutable struct T_Symbol <:S_ lines__ end) | (mutable struct T_ lines__ end))
# 	# @capture(:(struct Apple <:Fruit end), (struct T_ <: S_ end) | (struct T_ lines__ end))
# 	@show T S 
# end
# @capture(:(func(x::Int) = 1), (f_(args__) = body_) | (struct S s end))
# @show f args
# begin
# 	@capture(:(fruit::M1.Fruit), (_::pre_.T_))
# 	@show T, pre
# 	@capture(:(fruit::Vector{M1.Fruit}), (_::pre_.T_))
# 	@show T, pre

# 	@capture(:(fruit::Fruit), (P_::T_Symbol))
# 	@show T, P
# 	@capture(:(::Fruit), ::T_Symbol)
# 	@show T
# 	@capture(:(fruit::Vector{Fruit}), _::T_Symbol)
# 	@show T

# 	@capture(:(::Vector{Fruit}), ::T_Symbol)
# 	@show T
# end

@testset "not implemented" begin
	struct T1 <: AbstractVector{Int} end
	# @abstractbase struct T2 <: AbstractVector{Int} end
	@test_throws ImplementError @implement struct T3{N} <: T1 end
end
