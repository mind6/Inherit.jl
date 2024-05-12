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

# __precompile__(false)
"
Creates a new module that contains (i.e. imports) only the properties of `basemodule` which are Types and Modules (i.e. excluding any functions). You can evaluate method declarations in this module to get the signature, without modifying `basemodule` itself
"
function createshadowmodule(basemodule::Module)
	newmod = Module(:myshadow, true, true)

	### build a list of functions and extract their types. This helps us weed out properties like Symbol("#cost") which contains the type of the `cost` function
	functypes = Set{DataType}()
	for name in names(basemodule, all=true)
		if !isdefined(basemodule, name) continue end
		p = getproperty(basemodule, name)
		if p isa Function
			push!(functypes, typeof(p))
		end
	end
	# @show functypes

	### copy Types and Module properties from basemodule to the new module, excluding Types which are generated by function definitions.
	for name in names(basemodule, all=true)
		if !isdefined(basemodule, name) continue end
		p = getproperty(basemodule, name)
		if p isa Union{Type, Module} && p ∉ functypes
			# @show name p
			setproperty!(newmod, name, p)
		end
	end

	#adds the ability to invoke `newmod.eval(expr)` by passing the call to `Base.eval``
	# Base.eval(newmod, :(function eval(x) Base.eval(@__MODULE__, x) end))

	newmod
end

"""
this is used by __init__ so we throw errror directly instead of returning a throw error exception.
"""
function populatefunctionsignature!(decl::MethodDeclaration, defmodule::Module, T::Symbol, decls::Vector{MethodDeclaration})
	f = defmodule.eval(decl.line)		#evaluated in calling module without hygiene pass
	# f = Base.eval(shadow, line)		#evaluated in calling module without hygiene pass
	m = last_method_def(f)
	# parent_f = __module__.eval(:(function $(m.name) end))	#declare just the function in the original module. this allows us to store the correct func type in the signature. It will not create any methods in the parent module.
	# m_sig = set_sig_functype(__module__, m.sig, typeof(parent_f))

	# duplicate fields will be detected by the implementing struct. duplicate methods are detected by us.
	if !all(p->p.sig != m.sig, decls)
		# ret=reset_type() 	#clears everything we've seen so far about the type, so it isn't misused? how necessary is this?
		# if ret !== nothing
		# 	return ret
		# end
						
		# errorstr = "duplicate method definition at $(__source__.file):$(__source__.line)"
		errorstr = "method definition duplicates a previous definition: $(decl.line) "
		throw(InterfaceError(errorstr))
	end
	decl.sig = m.sig
	@debug "interface specified by $T: $(decl.sig), age $(m.primary_world)"

	#NOTE: evaluating `@doc comment $(nameof(f))` here will only have a temporary effect. To persist documentation it must be done at the module __init__
	# push!(DBM[identT], MethodDeclaration(MOD, T, line, comment, m_sig))
	# comment = nothing
	Base.delete_method(m)   # `WARNING: method deletion during Module precompile may lead to undefined behavior` This warning shows up even when deleting in module __init__.
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

"
This assumes the result will be evaluated inside basemodule. Prefixes are stripped from implmodule to handle situations when a module cannot follow a path that leads to itself.
"
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

function make_variable_tupletype(curmodule::Module, types::Type ...)
	curmodule.eval(:(Tuple{$(types...)}))
end

function set_sig_functype(curmodule::Module, sig::Type{<:Tuple}, functype::DataType)
	@assert !isempty(sig.types)
	if length(sig.types) == 1
		sig = make_variable_tupletype(curmodule, functype)
	else
		sig = make_variable_tupletype(curmodule, functype, sig.types[2:end]...)
	end
end

"prepend __ to function name"
function privatize_funcname(funcdef::Expr)::Expr
	MacroTools.postwalk(x->begin
		if x isa Expr && x.head == :call
			x.args[1] = Symbol("__", x.args[1]) 
		end
		x
	end, funcdef)
end

isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1
