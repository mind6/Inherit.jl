"""
Returns true if function is defined like `function myfunc(a,b) end`, i.e. with an empty body. If there is any code in the function body, even if it's only `nothing`, returns false
"""
function hasemptybody(ci::Core.CodeInfo)::Bool
	return length(ci.code) == 1 && ci.code[1] isa Core.ReturnNode && ci.code[1].val === nothing
end

function last_method_def(f::Function)::Method
	ms = methods(f).ms
	_, idx = findmax(m->m.primary_world, ms)
	ms[idx]
end

"converts syntax like `a.b.c.d` to AST"
function to_qualified_expr(initialargs::Symbol ...)::Union{Symbol, Expr}
	function f(curexpr::Union{Nothing, Expr}, args::Symbol ...)::Union{Symbol, Expr}
		if isempty(args)
			curexpr
		elseif length(args) == 1
			if curexpr === nothing
				args[1]
			else
				Expr(:., curexpr, QuoteNode(args[1]))
			end
		elseif length(args) > 1
			if curexpr === nothing
				f(Expr(:., args[1], QuoteNode(args[2])), args[3:end]...)
			else
				f(Expr(:., curexpr, QuoteNode(args[1])), args[2:end]...)
			end
		end
	end
	f(nothing, initialargs...)
end

"
Makes a valid `import` expression like `import modpath1.modpath2.modpath3: item`

`:(import \$modpath : \$item)` won't work even when `modpath` evaluates to `modpath1.modpath2.modpath3`

evalmodname: the module where the import statement will be evaluated. It helps to convert Main to .. in some situations
"
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

function lastsymbol(expr::Union{Symbol, Expr, QuoteNode})::Symbol
	if expr isa Symbol
		expr
	elseif expr isa QuoteNode
		expr.value
	elseif expr isa Expr
		lastsymbol(expr.args[end])
	end
end

function singular_or_plural(count::Int, singular::String, plural::Union{Missing, String}=missing)
	io = IOBuffer()
	if count == 1
		print(io, count, ' ', singular)
	else
		if plural === missing
			print(io, count, ' ', singular, 's')
		else
			print(io, count, ' ', plural)
		end
	end
	String(take!(io))
end

function tostring(modname::NTuple{N, Symbol}, typename::Symbol) where N
	io = IOBuffer()
	join(io, modname, '.')
	print(io, '.', typename)
	String(take!(io))
end

function tostring(ident::TypeIdentifier) 
	tostring(ident.modulefullname, ident.basename)
end

function getfuncname(decl::MethodDeclaration)::Symbol
	# nameof(decl.sig.parameters[1].instance)
	decl.funcname
end

# "
# get the module given its fullname and the module handle we currently have
# "
# function getmodule(curmod::Module, modulefullname::NTuple{N, Symbol})::Module where N
# 	### sometime curmod may have been created without the properties we need to follow the fullname path. However we can still find the module pointed to be modulefullname, by skipping over common prefixes.
# 	curmodfn = fullname(curmod)
# 	modulefullname = strip_prefix(modulefullname, curmodfn)
	
# 	for name in modulefullname
# 		# @assert hasproperty(curmod, name) 	#cannot use this due to bug in hasproperty FIXME: report this
# 		try
# 			curmod = getproperty(curmod, name)
# 		catch e
# 			if e isa UndefVarError
# 				error("""cannot reach $modulefullname from $curmodfn""")
# 			else
# 				throw(e)
# 			end
# 		end
# 	end
# 	curmod
# end

# const SHADOW_MODULE_CONST_SYMBOLS = Set{Symbol}([Symbol("#eval"), Symbol("#include"), :__Inherit_jl_SHADOW_SUBMODULE, :eval, :include])
"
Creates a new module that contains (i.e. imports) only the properties of `basemodule` which are Types and Modules (i.e. excluding any functions). You can evaluate method declarations in this module to get the signature, without modifying `basemodule` itself

`basemodule` is the module whose properties we want to import into the shadow module. This module must be the one we're precompiling, so it isn't closed to eval.
"
function createshadowmodule(basemodule::Module)::Module
	if isdefined(basemodule, H_SHADOW_SUBMODULE)
		@debug "Shadow module $(H_SHADOW_SUBMODULE) already exists"
	else
		Core.eval(basemodule, :(module $(H_SHADOW_SUBMODULE) end))
	end

	shadowmod = getproperty(basemodule, H_SHADOW_SUBMODULE)

	### build a list of functions and extract their types. This helps us weed out properties like Symbol("#cost") which contains the type of the `cost` function
	functypes = Set{DataType}()
	for name in names(basemodule; imported=true, all=true)
		if !isdefined(basemodule, name) continue end
		p = getproperty(basemodule, name)
		if p isa Function
			push!(functypes, typeof(p))
		end
	end
	# @show functypes

	### copy Types and Module properties from basemodule to the new module, excluding Types which are generated by function definitions.
	for name in names(basemodule; imported=true, all=true)
		if !isdefined(basemodule, name) continue end
		p = getproperty(basemodule, name)
		if p isa Union{Type, Module} && p ∉ functypes
			# @show name p
			if isdefined(shadowmod, name)
				setproperty!(shadowmod, name, p)
			else
				Core.eval(shadowmod, :(global $name = $p))
			end
		end
	end

	shadowmod
end

"Frees up as much memory used by a submodule as possible by assigning everything to nothing. Base usage of about 3.2kb tends to be left behind."
function cleanup_shadowmodule(shadowmod::Module)
	cleaned = 0
	errored = 0
	for name in names(shadowmod; imported=true, all=true)
		try
			setproperty!(shadowmod, name, nothing)
			cleaned += 1
		catch e
			errored += 1
		end
	end
	@debug "cleaned $cleaned properties from shadow module $shadowmod. $errored names could not be cleaned."
end

# """
# this is used by __init__ so we throw errror directly instead of returning a throw error exception.
# """
# function populatefunctionsignature!(decl::MethodDeclaration, defmodule::Module, T::Symbol, decls::Vector{MethodDeclaration})
# 	# we cannot privatize the name here because this is the actual function definition
# 	f = Core.eval(defmodule, decl.line)		#evaluated in calling module without hygiene pass
# 	# f = Base.eval(shadow, line)		#evaluated in calling module without hygiene pass
# 	m = last_method_def(f)
# 	# parent_f = __module__.eval(:(function $(m.name) end))	#declare just the function in the original module. this allows us to store the correct func type in the signature. It will not create any methods in the parent module.
# 	# m_sig = set_sig_functype(__module__, m.sig, typeof(parent_f))

# 	# duplicate fields will be detected by the implementing struct. duplicate methods are detected by us.
# 	if !all(p->p.sig != m.sig, decls)
# 		# ret=reset_type() 	#clears everything we've seen so far about the type, so it isn't misused? how necessary is this?
# 		# if ret !== nothing
# 		# 	return ret
# 		# end
						
# 		# errorstr = "duplicate method definition at $(__source__.file):$(__source__.line)"
# 		errorstr = "method definition duplicates a previous definition: $(decl.line) "
# 		throw(InterfaceError(errorstr))
# 	end

# 	decl.sig = m.sig
# 	@debug "interface specified by $T: $(decl.sig), age $(m.primary_world)"

# 	#NOTE: evaluating `@doc comment $(nameof(f))` here will only have a temporary effect. To persist documentation it must be done at the module __init__
# 	# push!(DBM[identT], MethodDeclaration(MOD, T, line, comment, m_sig))
# 	# comment = nothing
# 	@debug "dangling method $m left behind due to function signature extraction"
# 	modinfoT = getproperty(defmodule, H_COMPILETIMEINFO)
# 	push!(modinfoT.methods_to_delete, m)
# 	# Base.delete_method(m)	# `WARNING: method deletion during Module precompile may lead to undefined behavior` This warning shows up even when deleting in module __init__.
# end

function make_function_signature(shadowmodule::Module, functype::DataType, line::Expr)::Type{<:Tuple}
	f = Core.eval(shadowmodule, line)
	m = last_method_def(f)
	set_sig_functype(m.sig, functype)
end

"
Returns modulefullname without any prefix it may share with prefixfullname. May return an empty tuple.
"
function strip_prefix(modulefullname::NTuple{N, Symbol}, prefixfullname::NTuple{M, Symbol}) where {N, M}
	modulefullname[skip_prefix(modulefullname, prefixfullname):end]
end

"return the index of the first position in modulefullname and prefixfullname does not match"
function skip_prefix(modulefullname::NTuple{N, Symbol}, prefixfullname::NTuple{M, Symbol}) where {N, M}
	i = 1
	while i <= N && i <= M && modulefullname[i] == prefixfullname[i]
		i += 1
	end
	i
end
"
removes repetition of module names
"
function strip_self_reference(modulefullname::NTuple{N, Symbol}) where N
	types = Vector{Symbol}()
	push!(types, modulefullname[1])
	for i in 2:N
		if modulefullname[i] != modulefullname[i-1]
			push!(types, modulefullname[i])
		end
	end
	Tuple(types)
end

"""
	reducetype(expr, basemodule, basetype, implmodule, impltype)

Transform type annotations in an expression by replacing valid supertype references with a specific 
subtype. Given a subtyping specification (`impltype <: basetype`), this function identifies type 
annotations in the expression that refer to the supertype and reduces them to the subtype, ensuring 
the reduced type reference will resolve correctly.

The prefix matching logic determines whether a qualified type reference actually points to the 
intended supertype by checking if its module path is compatible with `basemodule`. This prevents 
incorrect transformations when different modules contain types with the same name.

Transformations applied:
- `::Fruit` → `::M2.Orange` (unqualified basetype)
- `::M1.Fruit` → `::M2.Orange` (when M1 matches or extends basemodule path)  
- `::Main.M1.M1.Fruit` → `::M2.Orange` (nested module paths that resolve to basemodule)
- `<:Fruit` → `<:M2.Orange` (type parameter bounds)

Types are NOT transformed when:
- Module qualifiers don't match basemodule (e.g., `::M2.M1.Fruit` when basemodule is `(:Main, :M1)`)
- They appear as specific type parameters in parametric types (e.g., `Vector{Berry}`)
- The module path cannot be resolved to the expected location

This ensures the reduced type reference (`implmodule.impltype`) will be findable from the evaluation 
context while avoiding false matches with same-named types in other modules.

# Example
```julia
# Transform interface method to work with specific implementation
reducetype(:(function f(x::M1.Fruit) end), (:Main, :M1), :Fruit, (:Main, :M2), :Orange)
# → function f(x::M2.Orange) end
```
"""
function reducetype(expr::Expr, basemodule::NTuple{N, Symbol}, basetype::Symbol, implmodule::NTuple{M, Symbol}, impltype::Symbol)::Expr where {N, M}
	implmodule = strip_prefix(implmodule, basemodule)

	function param_expr(P::Union{Symbol, Nothing})
		if P !== nothing
			Expr(:(::), P, to_qualified_expr(implmodule..., impltype))
		else
			Expr(:(::), to_qualified_expr(implmodule..., impltype))
		end
	end
	
	function matches_basemodule(pre::Union{Expr, Symbol})
		idx = N
		while @capture(pre, pre2_.$(basemodule[idx]))
			if lastsymbol(pre2) != basemodule[idx]
				idx -= 1
			end
			if idx == 0 break end
			pre = pre2
		end
		return idx > 0 && pre == basemodule[idx]		# all the prefixes were consumed while matching basemodule, we know it's a match
	end

	MacroTools.postwalk(x->begin
		pre = P = T = nothing

		#captures the unqualified basetype by itself and reduces it
		if (@capture(x, P_::T_Symbol) || @capture(x, ::T_Symbol)) && T == basetype 	
			param_expr(P)

		#captures qualified basetype, keep reducing the qualifiers as long as it ends with basemodule
		elseif (@capture(x, P_::pre_.T_) || @capture(x, ::pre_.T_)) && T == basetype
			if matches_basemodule(pre)
				param_expr(P)
			else
				x
			end

		#captures a ranged type parameter
		elseif (@capture(x, <:T_Symbol) || @capture(x, <:pre_.T_)) && T == basetype
			if pre === nothing || matches_basemodule(pre)
				Expr(:(<:), to_qualified_expr(implmodule..., impltype))
			else
				x
			end

		#nothing captured
		else
			x
		end
	end, expr)
end

"""
Given an expression that looks like `struct <typename> ... end` or `struct <typename>{...} ... end`, modify the expression into `struct S{<params[1]>, <params[2]>, ...} ... end` 

Note that <typename> is only expected to be found in one of the positions above. We process only the first occurrence of <typename>. If the input expression is not of the expected form the expression returned may be gibberish syntatically. We accept this limitation for simplicity while traversing different types of struct definitions.
"""
function replace_parameterized_type(ex::Expr, typename::Symbol, params::Vector{SymbolOrExpr})
	replaced = false
	MacroTools.prewalk(x->begin
		# global replaced
		if !replaced && (@capture(x, T_Symbol) || @capture(x, T_Symbol{__}))
			if T == typename
				replaced = true
				return Expr(:curly, T, params...)
			end
		end
		x
	end, ex)
end

function set_sig_functype(sig::Type{<:Tuple}, functype::DataType)
	@assert !isempty(sig.types)
	if length(sig.types) == 1
		sig = Tuple{functype}
	else
		sig = Tuple{functype, sig.types[2:end]...}
	end
end

"prepend __Inherit_jl_ to function name"
function privatize_funcname(funcdef::Expr)::Expr
	MacroTools.postwalk(x->begin
		if x isa Expr && x.head == :call
			x.args[1] = Symbol("__Inherit_jl_", x.args[1]) 
		end
		x
	end, funcdef)
end

################################################################################
#=
Originally in constructors.jl:

These functions help to implement the new() and super() special functions, as outlined in test/runnable_designs.jl.
=#

# Transform new calls in constructors
function transform_new_calls(constructor_expr, supertype_name=nothing)
   MacroTools.postwalk(constructor_expr) do x
      if @capture(x, new(args__))
         return :(return ($(args...),))
      elseif supertype_name !== nothing && @capture(x, super(args__))
			# funcname = "construct_$(supertype_name)"
			funcname = Symbol(:construct_, supertype_name)
         construct_call = :($funcname($(args...))...)
         return construct_call
      else
         return x
      end
   end
end

"""
Get the constructor function name for the closest immediate supertype of the given type which has a constructor.
Returns nothing if there's no supertype or no constructor available.
"""
function get_supertype_constructor_name(current_module::Module, current_type_name::Symbol)
    DBSPEC = getproperty(current_module, H_TYPESPEC)
    
    if !haskey(DBSPEC, current_type_name)
        return nothing
    end    
   
    # TODO: Implement actual supertype resolution logic
    # This should:
    # 1. Find the applicable supertype of current_type_name, which is a TypeIdentifier
    # 2. Return the appropriate construct_SuperTypeName symbol
    # 3. Handle cross-module cases properly
    return nothing  # placeholder
end

# Generate construct_TypeName function from constructor
function generate_construct_function(constructor_expr)
	@assert isexpr(constructor_expr, :function)

	# Extract function arguments and body
	type_name = constructor_expr.args[1].args[1]
	func_args = constructor_expr.args[1].args[2:end]
	func_body = constructor_expr.args[2]
	# @show dump(func_body)

	# Create the construct_TypeName function using expression tree
	fname = Symbol("construct_", type_name)
	fargs = Expr(:call, fname, func_args...)
	ftype = Expr(:(::), fargs, :Tuple)
	fdef = Expr(:function, ftype, func_body)
	return fdef
end

"""
Builds a dynamic import expression for multiple package names.

Creates an expression equivalent to `import pkg1, pkg2, ...` from a collection of package symbols.

# Arguments
- `pkgnames`: Symbols representing package names to import

# Returns
- `Expr`: An import expression that can be evaluated

# Examples
```julia
# Single package
expr = build_import_expr(:PkgTest1)
# Returns: :(import PkgTest1)

# Multiple packages  
expr = build_import_expr(:PkgTest1, :PkgTest2, :DataFrames)
# Returns: :(import PkgTest1, PkgTest2, DataFrames)
```
"""
function build_import_expr(pkgnames::Symbol...)::Expr
    if length(pkgnames) == 0
        throw(ArgumentError("At least one package name must be provided"))
    end
    # Each package name needs to be wrapped in Expr(:., symbol) for proper import syntax
    import_args = [Expr(:., pkg) for pkg in pkgnames]
    Expr(:import, import_args...)
end