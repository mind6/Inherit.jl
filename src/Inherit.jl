"""
Inherit.jl let's the user inherit fields and interface definitions from a supertype. The macro @abstractbase declares an abstract supertype with inheritable fields and required method definitions. The @implement macro creates the concrete type that implements an @abstractbase.

Parametric types and constructors are now supported.

# Planned features

A third macro, @interface, is planned to be added. It will be used to create a container for method declarations required for subtypes. While a concrete type may implement only one @abstractbase, multiple @interface's may be implemented. It may become possible to add an @interface to an existing concrete type, like Holy Traits.

# Limitations

Like Julia types, inheritance definitions should be given in the order of their dependencies. 

Short form function definitions such as `f() = nothing` are not supported for method declaration; use the long form `function f() end` instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.
"""
module Inherit
export @abstractbase, @implement, @interface, @postinit, @verify_interfaces, isprecompiling, InterfaceError, ImplementError, SettingsError, (<--), setglobalreportlevel, setreportlevel, ThrowError, ShowMessage, SkipInitCheck, build_import_expr

using MacroTools

### extensions
macro test_nothrows end
export @test_nothrows


function warmup_import_package end
export warmup_import_package

__precompile__(true)

include("types.jl")

@enum ReportLevel ThrowError ShowMessage
global reportlevel::ReportLevel = ThrowError

# name of a user module's compile time info
const H_COMPILETIMEINFO::Symbol = :__Inherit_jl_COMPILETIMEINFO

# We use exactly one shadow module per user module of Inherit.jl. We try to import everything needed to evaluate function signatures into this shadow module. This is preferred over creating potentially hundreds of unique shadow modules. If using a single evaluation module won't work for some feature, we simply won't support that feature.
const H_SHADOW_SUBMODULE::Symbol = :__Inherit_jl_SHADOW_SUBMODULE

include("utils.jl")
include("publicutils.jl")

"""
	setup_module_db(mod::Module)

Initialize the module-level data structures needed by the Inherit.jl package.
This function must be called before any other functions that manipulate the module's
inheritance database.

# Side effects:
- Creates CompiletimeModuleInfo instance for the module
- This is idempotent - only initializes structures if they don't already exist
"""
function setup_module_db(mod::Module)
	if !isdefined(mod, H_COMPILETIMEINFO)
		Core.eval(mod, quote
			const $H_COMPILETIMEINFO = Inherit.CompiletimeModuleInfo() #this being type stable is quite helpful to performance
		end)
	end
end

"""
Resolves a supertype expression into a TypeIdentifier and CompiletimeModuleInfo of the supertype's module.

If the supertype is not an @abstractbase, returns (nothing, modinfo).

If the supertype is defined in a foreign module, the CompiletimeModuleInfo will contain the foreign module's CompiletimeModuleInfo.
"""
function process_supertype(currentmod::Module, S::Union{Symbol, Expr})::Tuple{Union{Nothing, TypeIdentifier}, Union{Nothing, CompiletimeModuleInfo}}
	objS = Core.eval(currentmod, S)		
	moduleS = parentmodule(objS)		#whichever module the supertype was defined in
	nameS = nameof(objS)			
	identS = TypeIdentifier((fullname(moduleS), nameS))

	if !isdefined(moduleS, :__Inherit_jl_COMPILETIMEINFO)
		@debug "Subtyping from $moduleS.$nameS, but $moduleS is has no compile time info."
		return nothing, nothing
	end	
	modinfo = getproperty(moduleS, H_COMPILETIMEINFO)	#this modinfo of the supertype's module; it can be the currentmod or a foreign module
	# @show fullname(moduleS), fullname(currentmod)

	if !haskey(modinfo.localtypespec, nameS)
		@debug "supertype $nameS not found in $moduleS -- It needs to have been declared with @abstractbase"
		return nothing, modinfo
	end
	
	identS, modinfo
end

include("abstractbase.jl")
include("constructors.jl")


"""
This verifies the known interfaces of the current module. It should be placed at the end of the module, after all other Inherit macros have been executed.

The macro runs as a compile time verification step. The presence of this macro is optional. If not present, clients of the module should notice no difference.
"""
macro verify_interfaces()
	n_supertypes = n_subtypes = n_signatures = n_errors = 0

	function handle_error(errorstr::String)
		n_errors += 1
		if Inherit.reportlevel == Inherit.ThrowError
			throw(ImplementError(errorstr))
		else
			@assert Inherit.reportlevel == Inherit.ShowMessage
			@error errorstr
		end
	end
	modinfo = getproperty(__module__, H_COMPILETIMEINFO)
	LOCALMOD = Base.fullname(__module__)

	### create our singleton instance of the shadow module, if not already created by an earlier @abstractbase or @implement macro
	shadowmodule = Inherit.createshadowmodule(__module__)

	### for each supertype of some type defined in this module...
	for (identS, decls) ∈ modinfo.method_decls
		n_supertypes += 1
		SUBTYPES = modinfo.subtypes[identS]
		if Base.isempty(SUBTYPES)	
			@debug "$(Inherit.tostring(identS)) has no subtypes; not requiring method implementations"
			continue 
		end

		n_subtypes += Base.length(SUBTYPES)
		n_signatures += Base.length(decls)

		### even with no subtypes, we need to go through decls to document interfaces
		@debug "Inherit.jl requires interface definitions defined in base type $(Inherit.tostring(identS)) to be satisfied"

		### for each required method declared by the supertype (including types it inherited)...
		for decl in decls							
			@assert decl.sig !== nothing

			__defmodule__ = Inherit.find_supertype_module(
				getproperty(__module__, SUBTYPES[1]), decl.defident)
	
			funcname = decl.funcname

			### get the method table of the declared function
			func = Base.getproperty(__defmodule__, funcname)
			mt = Base.methods(func)
			if mt === nothing || Base.isempty(mt)
				errorstr = "No methods defined for `$(Base.nameof(__defmodule__)).$funcname`. A method must exist which satisfies:\n$(decl.line)"
				handle_error(errorstr)
				continue
			end

			@debug "$(identS.basename) requires $(decl.sig) for each of $(join(SUBTYPES, ", "))"
			for subtype in SUBTYPES		# each subtype must satisfy each interface signature
				@debug "checking subtype $subtype"

				type_satisfied = false

				### for each subtype it only needs to satisfy the concrete sig, where each occurrence of type T has been replaced with type subtype
				reducedline = Inherit.reducetype(decl.line, 
					decl.defident.modulefullname, decl.defident.basename, 
					LOCALMOD, subtype)
				@debug "evaluating $reducedline"

				### we rename the reduced function before evaluating to get the signature, in order to prevent overwriting existing implementing method
				reducedline = Inherit.privatize_funcname(reducedline)

				### sneakily use the shadow module to evaluate the function signature
				f = Core.eval(shadowmodule, reducedline) 
				reducedmethod = Inherit.last_method_def(f)

				### restore the functype signature from the original declaration
				reducedsig = Inherit.set_sig_functype(reducedmethod.sig, decl.sig.types[1])

				for m in mt				#methods implemented on function of required sig
					if decl.sig <: m.sig	# being a supersig in the unmodified version satisfies all subtypes. 
						type_satisfied = true
						@debug "all subtypes have been satisfied by $(m.sig)"
					elseif reducedsig <: m.sig
						@debug "subtype $(Inherit.tostring(LOCALMOD, subtype)) satisfied by $(m.sig)"
						type_satisfied = true
					end							
				end
				if !type_satisfied
					errorstr = "Subtype $(Inherit.tostring(LOCALMOD, subtype)) must satisfy $reducedsig, declared as:\n$(decl.line)"
					handle_error(errorstr)
				end
			end	#end subtypes
		end #end decls
	end #end DMB

	Inherit.cleanup_shadowmodule(shadowmodule)

	summarystr = """[$(BLUE)$(BOLD)Inherit.jl$(END)] processed $(join(LOCALMOD, '.')) with $(Inherit.singular_or_plural(n_supertypes, "supertype")) having $(Inherit.singular_or_plural(n_signatures, "method requirement")). $(Inherit.singular_or_plural(n_subtypes, "subtype was", "subtypes were")) checked with $(Inherit.singular_or_plural(n_errors, "missing method"))."""
	@info summarystr
end 


"
Creates a Julia `struct` or `mutable struct` type which contains all the fields of its supertype. Method interfaces declared (and inherited) by the supertype are required to be implemented.

Requires a single expression of one of following forms:

	struct T <: S ... end
	mutable struct T <: S ... end

__Mutability__ must be the same as the supertype's mutability.

Method declarations may be from a __foreign module__, in which case method implementations must be added to the foreign module's function. If there is no name clash, the foreign modules's function is _automatically imported_ into the __implementing module__ (i.e. your current module). If there is a name clash, you must qualify the function name with the foreign module's name.
"
macro implement(ex)
	setup_module_db(__module__)

	T = P = nothing
	local ismutable
	if @capture(ex, struct T_Symbol<:S_ lines__ end)
		ismutable = false
	elseif @capture(ex, struct T_Symbol{P__}<:S_ lines__ end)
		ismutable = false
	elseif @capture(ex, mutable struct T_Symbol<:S_ lines__ end)
		ismutable = true
	elseif @capture(ex, mutable struct T_Symbol{P__}<:S_ lines__ end)
		ismutable = true
	else
		errorstr = "Cannot parse the following as a struct subtype:\n $ex"
		return :(throw(ImplementError($errorstr)))
	end
	# dump(S; maxdepth=16)

	### evaluate the supertype expression so we can get the correct module
	identS, modinfoS = process_supertype(__module__, S)
	if identS === nothing
		errorstr = "$S is not a valid type for implementation by $T; it was not declared with @abstractbase"
		return :(throw(ImplementError($errorstr)))
	end

	specS = modinfoS.localtypespec[identS.basename]		#using S is not reliable here because it may have module path in it
	if ismutable != specS.ismutable
		errorstr = "mutability of $S is $(specS.ismutable) but that of $T is $ismutable"
		return :(throw(ImplementError($errorstr)))
	end
	# recording as subtype in the local module's dict. this activates any method requirements for the supertype
	modinfoT = getproperty(__module__, H_COMPILETIMEINFO)
	localsubtypes = modinfoT.subtypes

	### add T as a subtype of S, and import any method declarations from the supertype's module
	if modinfoS != modinfoT		#foreign module
		if !haskey(localsubtypes, identS)
			localsubtypes[identS] = Vector{Symbol}()
		end
		modinfoT.method_decls[identS] = modinfoS.method_decls[identS]
	else						#local module
		@assert haskey(localsubtypes, identS)
	end
	push!(localsubtypes[identS], T)

	### add the type parameters if they exist
	if !isempty(specS.typeparams) || P !== nothing
		if P === nothing 
			P = Vector{SymbolOrExpr}() 
		else
			P = Vector{SymbolOrExpr}(P)  #convert the type from Vector{Any} output by MacroTools, to emphasize what we're expecting.
		end
		prepend!(P, specS.typeparams)
		# ex.args[2].args[2] = Expr(:curly, T, P...)
		ex = replace_parameterized_type(ex, T, P)
	end

	### look for any constructor definitions and transform them
	lines = ex.args[3].args
	find_and_transform_constructors!(lines, T, S, __module__)

	### add the fields for the supertype to the front of list for derived type
	prepend!(lines, specS.fields)	

	esc(ex)		#hygiene pass will resolve ex to the Inherit module if not escaped
end	#end @implement


"
An @abstractbase follows Julia's type hierarchy; a concrete type may only implement one abstractbase. A @interface is similar in some ways to Holy traits; a type may implement multiple interfaces in addition to its abstractbase. A interface can span type hierarchies, but it may only be used to inherit fields and function definition requirements. It cannot be used as a container element or object type (while carrying the behavior of interfaces).

Can recreate the struct parameterized by the interface, this allows dispatch only on type, or on both type and interface. Basically, store the list of interfaces in the type parameters, and create default constructors that don't require the interface parameters.
"
macro interface(ex)
	esc(ex)
end

function (<--)(a ,b)
	@error "$a does not implement interface $b"
	false
end

#=
This can execute when precompiling or when module is revised.
=#
begin
	@info "reached bottom of Inherit.jl" isprecompiling()
end

end # module Inherit
