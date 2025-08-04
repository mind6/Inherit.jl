#=
Code which are no longer used, but may be useful for reference.
=#

"""
Returns true if function is defined like `function myfunc(a,b) end`, i.e. with an empty body. If there is any code in the function body, even if it's only `nothing`, returns false
"""
function hasemptybody(ci::Core.CodeInfo)::Bool
	return length(ci.code) == 1 && ci.code[1] isa Core.ReturnNode && ci.code[1].val === nothing
end

if VERSION.minor >= 11
	@testset "detecting empty function body" begin
		function f1() end
		function f2 end
		function f3 end

		function f2() println("this function does something") end
		function f3() nothing end

		@test Inherit.hasemptybody(code_typed(f1)[1].first)	#prototype never implemented
		@test !Inherit.hasemptybody(code_typed(f2)[1].first) #has some implementation
		@test Inherit.hasemptybody(code_typed(f3)[1].first) #equivalent to f1
	end
end

#######################################################################################
"""
    to_import_expr(item::Symbol, modname::NTuple{N, Symbol}, evalmodname::NTuple{M, Symbol})

Generates a syntactically correct import expression that brings `item` from module `modname` 
into scope when evaluated from module `evalmodname`. The function handles relative import 
paths automatically, using `..` notation when importing from parent modules or siblings.

# Arguments
- `item`: Symbol to import (e.g., `:MyType`, `:myfunction`)
- `modname`: Full module path where `item` is defined, as tuple of symbols 
  (e.g., `(:Main, :MyPackage, :SubModule)`)
- `evalmodname`: Full module path where the import statement will be evaluated
  (e.g., `(:Main, :MyPackage, :AnotherModule)`)

# Why use this function
Julia's import syntax requires literal module paths - you cannot use variables or 
interpolated expressions like `:(import \$modpath : \$item)`. This function constructs 
the proper `Expr(:import, ...)` with the correct relative path syntax that Julia expects.

# How it works
The function analyzes the relationship between `modname` and `evalmodname` to determine:
- Absolute imports when modules are unrelated
- Relative imports with `.` when importing from submodules  
- Relative imports with `..` when importing from parent/sibling modules

# Examples
```julia
# Import from sibling module
to_import_expr(:cost, (:Main, :M1), (:Main, :M2))
# Returns: :(import ..M1: cost)

# Import from parent module  
to_import_expr(:MyType, (:Main, :Package), (:Main, :Package, :SubMod))
# Returns: :(import ..: MyType)

# Import from unrelated module
to_import_expr(:func, (:Main, :Other), (:Main, :Current))  
# Returns: :(import Main.Other: func)
```
"""
function to_import_expr(item::Symbol, modname::NTuple{N, Symbol}, evalmodname::NTuple{M, Symbol})::Expr where {N, M}
	modname = strip_self_reference(modname)
	evalmodname = strip_self_reference(evalmodname)
	# @show modname evalmodname
	symbols = Vector{Symbol}()

	i = skip_prefix(modname, evalmodname)
	if i == 1	#no relationship, use absolute path
		append!(symbols, modname)
	elseif i > length(evalmodname)	#mod is a submodule of evalmod
		@assert i <= length(modname) "unexpected import from same module $(modname) by $(evalmodname)"
		push!(symbols, :.)
		append!(symbols, modname[i:end])
	else	#mod can be reached from an ancestor of evalmod
		@assert i <= length(evalmodname) "unexpected import from same module $(modname) by $(evalmodname)"
		iancestor = i - 1
		backlevels = length(evalmodname) - iancestor

		if i > length(modname) 	### importing an ancestor itself, extra .. plus ancestor name
			for k in 1:(backlevels+1)
				push!(symbols, :., :.)
			end
			push!(symbols, modname[iancestor])	
		else	 ### importing a descendant of an ancestor, no extra .. no ancestor name
			for k in 1:(backlevels)
				push!(symbols, :., :.)
			end
		end

		for k in iancestor+1:length(modname)
			push!(symbols, modname[k])
		end
	end

	Expr(:import, 
		Expr(:(:), 
			Expr(:., symbols...), 
			Expr(:., item)))
end

function to_import_expr(itemS::Symbol, typeS::Union{Symbol, Expr})::Expr
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




