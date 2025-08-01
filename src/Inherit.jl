"""
Inherit.jl let's the user inherit fields and interface definitions from a supertype. There are two macros which provide abstract templates for concrete types: @abstractbase which declares an abstract supertype with inheritable fields and required method definitions, and @interface which declares a container rather than supertype, while providing the same inheritance features. The @implement macro creates the concrete type that implements either or both of these templates. While a concrete type may  implement only one @abstractbase, multiple @interface's may be implemented.
	
We have steered away from using the term "traits" to avoid confusion with extensible [Holy traits](https://invenia.github.io/blog/2019/11/06/julialang-features-part-2/) widely used in Julia libraries. While @interface's can be multiplely inherited, they cannot be added to an existing concrete type from another package. 

# Limitations

Short form function definitions such as `f() = nothing` are not supported for method declaration; use the long form `function f() end` instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.

Just like Julia types, definitions should be given in the order of their dependencies. While out-of-order code can work in some circumstances, we don't test for them. Within a given type, field and method definitions must be unique.

Inherit.jl has no special knowledge about constructors (inner or otherwise). They're treated like normal functions.

A method's signature given *only* by its positional arguments is unique. If you define a method with the same positional arguments but different keyword arguments from a previously defined method, it will overwrite the previous method. Keyword arguments simply do not participate in method dispatch.

# Special notes

A parametric type signature can be supertype of abstract type signature
	Tuple{typeof(f), Real} <: Tuple{typeof(f), T} where T<:Number

`typeof(f).name.mt` grows for each evaluation of method definition, even if it overwrites a previous definition. It is not the same as `methods(f)`

"""
module Inherit
export @abstractbase, @implement, @interface, @postinit, @verify_interfaces, isprecompiling, InterfaceError, ImplementError, SettingsError, (<--), setglobalreportlevel, setreportlevel, ThrowError, ShowMessage, SkipInitCheck, build_import_expr

using MacroTools

macro test_nothrows end
export @test_nothrows


function warmup_import_package end
export warmup_import_package

__precompile__(true)


SymbolOrExpr = Union{Symbol, Expr}

#super type identifier
TypeIdentifier = @NamedTuple{
	modulefullname::Tuple, 	#module where the supertype was originally defined
	basename::Symbol}			#name of the supertype

TypeSpec = @NamedTuple{
	ismutable::Bool,			#whether or not the fields of this type are mutable
	typeparams::Vector{SymbolOrExpr},  #expressions that define the type parameters, including those inherited from supertype
	fields::Vector{Expr}		#expressions that define the type's fields (including those inherited from supertype)	
}

struct MethodDeclaration 
	defmodulename::Tuple 	#module where the declaration was originally defined. helps with line reduction
	defbasename::Symbol		#base type name where the declaration was originally defined. helps with line reduction
	line::Expr	 				#the original statement AST
	linecomment::Union{Nothing, String, Expr}		#String or Expr(:string ...) that documents the line
	funcname::Symbol			#name of function. must be determined at type definition time. It cannot be extracted from sig because it may be empty until module __init__.
	functype::DataType			#the original functype evaluated in original module. This is key to signature checking, and it results from the only evaluation we make into a non-temporary module.
	sig::Type{<:Tuple}		#the original sig evaluated in original module
end

"""
The location of the original definition of a method. 
"""
function typeidentifier(decl::MethodDeclaration)::TypeIdentifier
	TypeIdentifier((decl.defmodulename, decl.defbasename))
end

struct ConstructorDefinition 
	defmodulename::Tuple 	#module where the declaration was originally defined. helps with line reduction
	defbasename::Symbol		#base type name where the declaration was originally defined. helps with line reduction
	original_expr::Expr
	transformed_expr::Expr
	linecomment::Union{Nothing, String, Expr}
end

struct InterfaceError <: Exception
	msg::String
end
struct ImplementError <: Exception
	msg::String
end
struct SettingsError <: Exception
	msg::String
end

function Base.show(io::IO, x::Union{InterfaceError, ImplementError, SettingsError})
	print(io, nameof(typeof(x)), ": ")
	print(io, x.msg)
end

@enum ReportLevel ThrowError ShowMessage

"""
There is one instance for each module which uses Inherit.jl. It is built up when @abstractbase and @implement macros execute at compile time. 

It must contain strings and expressions that describe the types, but not runtime instances themselves. It may contain compile time state and evaluated function objects. These function objects can be called during module __init__, as per PkgTest4.jl
"""
@kwdef struct CompiletimeModuleInfo
	# abstract base type (defined in local module only) => flags and fields for this type
	localtypespec::Dict{Symbol, TypeSpec} = Dict{Symbol, TypeSpec}()

	# abstract base type (local or foreign) => list of required methods (including those inherited from supertypes)
	methods::Dict{TypeIdentifier, Vector{MethodDeclaration}} = Dict{TypeIdentifier, Vector{MethodDeclaration}}()

	# abstract base type (local or foreign) => list of constructor definitions
	consdefs::Dict{TypeIdentifier, Vector{ConstructorDefinition}} = Dict{TypeIdentifier, Vector{ConstructorDefinition}}()

	# abstract base type (local or foreign) => list of local subtypes
	subtypes::Dict{TypeIdentifier, Vector{Symbol}} = Dict{TypeIdentifier, Vector{Symbol}}()

	# (modulefullname,funcname) pairs that have been auto imported
	imported::Set{TypeIdentifier} = Set{TypeIdentifier}()


	# # methods which we added during compilation of the current module (to get signatures of functions, both defined locally and imported from foreign modules) to be deleted during __init__ (post precompilation)
	# methods_to_delete::Vector{Method} = Vector{Method}()

	# # user functions to be called at the end of __init__ (after Inherit.jl completes self registration)
	# postinit::Vector{Function} = Vector()

end

# name of a user module's compile time info
const H_COMPILETIMEINFO::Symbol = :__Inherit_jl_COMPILETIMEINFO

# place holder in a user module A which temporarily imports a client module B , because B wants to evaluate function signatures in A with types available in B.
# const H_TEMPORARY_CLIENTMODULE::Symbol = :__Inherit_jl_TEMPORARY_CLIENTMODULE

# We use exactly one shadow module per user module of Inherit.jl. We try to import everything needed to evaluate function signatures into this shadow module. This is preferred over creating potentially hundreds of unique shadow modules. If using a single evaluation module won't work for some feature, we simply won't support that feature.
const H_SHADOW_SUBMODULE::Symbol = :__Inherit_jl_SHADOW_SUBMODULE

#NOTE: this is a runtime map where user modules self-register with Inherit.jl (both when isprecompiling() is false and when it is true).
# const FULLNAME_TO_MODULE = Dict{Tuple, Module}()	#points from fullname(mod) to the mod. 

global reportlevel::ReportLevel = ThrowError

include("utils.jl")
include("publicutils.jl")

"""
	setup_module_db(mod::Module)

Initialize the module-level data structures needed by the Inherit.jl package.
This function must be called before any other functions that manipulate the module's
inheritance database.

# Side effects:
- Creates CompiletimeModuleInfo instance for the module
- Sets up module.__init__ to verify implementations when the module is loaded
- This is idempotent - only initializes structures if they don't already exist
"""
function setup_module_db(mod::Module)
	if !isdefined(mod, H_COMPILETIMEINFO)
		Core.eval(mod, quote
			const $H_COMPILETIMEINFO = Inherit.CompiletimeModuleInfo() #this being type stable is important for module __init__ speed
		end)
		# Core.eval(mod, quote
		# 	global $H_TEMPORARY_CLIENTMODULE::Union{Module, Nothing} = nothing
		# end)

		# initexp = create_module__init__()
		# Core.eval(mod, initexp) # NOTE: do not use rmlines on this eval	end
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
	
	### import all the foreign function declarations into the current module. Any methods we define will live with the foreign module's functions; they not not create our own function.
	# currentfullname = fullname(currentmod)
	# for decl in modinfo.methods[identS]
	# 	if decl.defmodulename == currentfullname continue end	#no need to import

	# 	funcname = decl.funcname
	# 	identF = TypeIdentifier((decl.defmodulename, funcname))

	# 	if !isdefined(currentmod, funcname)
	# 		expr = to_import_expr(funcname, decl.defmodulename, currentfullname)
	# 		# currentmod.eval(:(export $funcname))	#NOTE: export must come before the symbol import, in order to work. I think we may not actually want this. Allow export lists to be explicit.
	# 		Core.eval(currentmod, expr)
	# 		push!(modinfo.imported, identF)
	# 		@debug "auto imported with `$expr`"
	# 	elseif identF ∉ modinfo.imported
	# 		@warn "$(nameof(currentmod)) already has a symbol `$funcname`. To implement $(decl.line) you should write the function name as `$(tostring(decl.defmodulename, funcname))`"
	# 	end
	# end
	
	identS, modinfo
end

"
Creates a Julia abstract type, while allowing field and method declarations to be inherited by subtypes created with the `@implement` macro.

Requires a single expression of one of following forms:

	struct T ... end
	mutable struct T ... end
	struct T <: S ... end
	mutable struct T <: S ... end

Supertype __S__ can be any valid Julia abstract type. In addition, if __S__ was created with `@abstractbase`, all its fields and method declarations will be prepended to __T__'s own definitions, and they will be inherited by any subtype of __T__. 

__Mutability__ must be the same as the supertype's mutability.
"

include("refactored_abstractbase.jl")
include("constructors.jl")

# function create_module__init__()::Expr
# 	# TODO: this was hard won knowledge; implement it in some function?
# 	# ### Find whether Inherit module is in Debug logging level. If it is, error messages will be printed in place of exceptions, because exceptions cannot be caught from module __init__ 
# 	# init_throwsexception = let
# 	# 	log_data = Base.CoreLogging.process_logmsg_exs(Inherit, nothing, nothing, Debug, "hello")
# 	# 	logger = Base.CoreLogging.current_logger_for_env(Debug, log_data._group, log_data._module)

# 	# 	# @show @macroexpand @debug "hello there"
# 	# 	# @show state = Base.CoreLogging.current_logstate()  This doesn't return the correct logger for Inherit
# 	# 	logger === nothing || !Logging.shouldlog(logger, Debug, Inherit, :Inherit, nothing)
# 	# end
# 	# if (!init_throwsexception)
# 	# 	@warn "any exceptions will show as error messages only, to allow tests to complete" init_throwsexception
# 	# end


# 	modinfo_node = QuoteNode(H_COMPILETIMEINFO)
# 	"
# 	In the user module's init, we need to throw exceptions directly, since there's no eval on the return value.

# 	NOTE that only the quoted expression has access to the correct @__MODULE__. Any utility functions of Inherit.jl must receive this as a parameter, instead of invoking @__MODULE__ directly.

# 	NOTE that we should specify standard library functions explicitly, so we don't inadvertently invoke functions defined locally in the init's module.
# 	"
# 	quote function __init__()
# 		if isprecompiling() # this is only needed during precompilation to find the supertype's module object. It adds 40ms to module load time just by itself
# 			Inherit.FULLNAME_TO_MODULE[Base.fullname(@__MODULE__)] = @__MODULE__	
# 		end
# 		# if !isdefined(@__MODULE__, $modinfo_node)
# 		# 	println("I don't require any definitions")
# 		# 	return
# 		# end
# 		modinfo = getproperty(@__MODULE__, $modinfo_node)
# 		# # @debug "$(@__MODULE__) contains module entry $modinfo"

# 		# # if Inherit.isprecompiling()	#Can't use eval when precompiling. Precompilation "closes" a package. If Pkg2 loads precompiled Pkg1, Pkg1.__init__() will fire, which fails when trying to eval into closed Pkg1.
# 		# # 	@goto process_postinit 
# 		# # end
# 		# # @label process_postinit
# 		# println("processing $(Base.length(modinfo.postinit)) module inits...")
# 		if !isprecompiling()
# 			for m in modinfo.methods_to_delete 
# 				Base.delete_method(m)
# 			end
# 		end

# 		for f in modinfo.postinit 
# 			f()
# 		end

# 	end end 	#end quote
# end

"""
This verifies the known interfaces of the current module. It should be placed at the end of the module, after all other Inherit macros have been executed.

The macro runs as a compile time verification step. The presence of this macro is optional. If not present, clients of the module should notice no difference.
"""
macro verify_interfaces()
	# Inherit.FULLNAME_TO_MODULE[Base.fullname(__module__)] = __module__	# at compile time we need to update this map for self-lookup. The dependencies update to this same map but through runtime __init__.

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
	shadowmodule = Inherit.createshadowmodule(__module__)
	# LM_HANDLE  = Symbol(:__Inherit_jl_, LOCALMOD[end])

	### for each supertype of some type defined in this module...
	for (identS, decls) ∈ modinfo.methods
		n_supertypes += 1
		# __supertypemod__ = Inherit.getmodule(identS.modulefullname)
		# isforeign = __supertypemod__ != @__MODULE__
		# if isforeign	#skips installing a handle if local module, so we don't litter a module with handles unnecessarily.
		# 	setproperty!(__supertypemod__, LM_HANDLE, @__MODULE__)
		# end
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
			# __defmodule__ = Inherit.FULLNAME_TO_MODULE[decl.defmodulename]
			@assert decl.sig !== nothing
			# if decl.sig === nothing
			# 	ret = Inherit.populatefunctionsignature!(decl, __defmodule__, identS.basename,  decls)
			# 	@assert decl.sig !== nothing
			# end
			originalIdentS = typeidentifier(decl)
			__defmodule__ = Inherit.find_supertype_module(
				getproperty(__module__, SUBTYPES[1]), originalIdentS)
	
			funcname = decl.funcname

			### make sure the defmodule can access the implementing type
			isforeign = __defmodule__ != __module__
			# if isforeign		#skips installing a handle if local module, so we don't litter a module with handles unnecessarily.
			# 	@debug "declaration was for $__defmodule__ but we're in $(__module__); not documenting"
			# 	Base.setproperty!(__defmodule__, H_TEMPORARY_CLIENTMODULE, __module__)
			# elseif decl.linecomment !== nothing 	#for local module, set the @doc for method declarations
			# 	# NOTE: no longer needed because declarations are now documented in process_method_declaration()
			# 	# @debug "documenting `$funcname` with `$(decl.linecomment)`"
			# 	# expr = :(@doc $(decl.linecomment) $funcname)
			# 	# Core.eval(__module__, expr)	#documents the method declaration not in the defining module, but the implementing module
			# end

			### do not require method table if there are no subtypes

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
				# f = sig.parameters[1].instance		#the function is still available even if all methods have been deleted
				# mt = methods(f) 		
				@debug "checking subtype $subtype"

				type_satisfied = false

				# for each subtype it only needs to satisfy the concrete sig, where each occurrence of type T has been replaced with type subtype
				# @show decl
				reducedline = Inherit.reducetype(decl.line, 
					decl.defmodulename, decl.defbasename, 
					LOCALMOD, subtype)
				@debug "evaluating $reducedline"

				###we rename the reduced function before evaluating to get the signature, in order to prevent overwriting existing implementing method
				reducedline = Inherit.privatize_funcname(reducedline)
				f = Core.eval(shadowmodule, reducedline) # TODO: this is the big blocker of our precompile only verification -- we cannot evaulate into a closed foreign module __defmodule__
				reducedmethod = Inherit.last_method_def(f)
				#restore the functype signature from the original declaration
				reducedsig = Inherit.set_sig_functype(reducedmethod.sig, decl.sig.types[1])
				#this is safe to delete because it's on the renamed function
				# @debug "dangling method $reducedmethod left behind due to function signature replacement"
				# push!(modinfo.methods_to_delete, reducedmethod)
				# Base.delete_method(reducedmethod)  #NOTE: it's okay to delete_method here because we're in the module init not the precompilation phase.						

				for m in mt				#methods implemented on function of required sig
					if decl.sig <: m.sig	# being a supersig in the unmodified version satisfies all subtypes. 
						type_satisfied = true
						@debug "all subtypes have been satisfied by $(m.sig)"
						# @goto all_types_satisfy_sig
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

			# @info "all checked"
			# @label all_types_satisfy_sig
			# @info "$decl done"
			#FIXME: report "Unreachable reached at" error with label here
		end #end decls
	end #end DMB

	Inherit.cleanup_shadowmodule(shadowmodule)

	summarystr = """Inherit.jl: processed $(join(LOCALMOD, '.')) with $(Inherit.singular_or_plural(n_supertypes, "supertype")) having $(Inherit.singular_or_plural(n_signatures, "method requirement")). $(Inherit.singular_or_plural(n_subtypes, "subtype was", "subtypes were")) checked with $(Inherit.singular_or_plural(n_errors, "missing method"))."""
	@info summarystr
end 

# "
# Requires a single function definition expression.

# The function will be executed after Inherit.jl verfies interfaces. You may have any number of @postinit blocks; they will execute in the order in which they were defined.

# The function name must be different from `__init__`, or it will overwrite Inherit.jl interface verification code. Furthermore, you module must not contain any function named `__init__`. Initialization code must use this macro with a changed name, or with an anonymous function. For example, 

# 	@postinit function __myinit__() ... end
# 	@postinit () -> begin ... end

# "
# macro postinit(ex)
# 	@assert MacroTools.isdef(ex) "function definition expected"
# 	setup_module_db(__module__)
# 	modinfo = getproperty(__module__, H_COMPILETIMEINFO)
# 	push!(modinfo.postinit, Core.eval(__module__, ex))
# 	@debug "module entry $modinfo added under $__module__"

# 	nothing
# end

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
	if @capture(ex, struct T_Symbol<:S_ fields__ end)
		ismutable = false
	elseif @capture(ex, struct T_Symbol{P__}<:S_ fields__ end)
		ismutable = false
	elseif @capture(ex, mutable struct T_Symbol<:S_ fields__ end)
		ismutable = true
	elseif @capture(ex, mutable struct T_Symbol{P__}<:S_ fields__ end)
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

	if modinfoS != modinfoT		#foreign module
		if !haskey(localsubtypes, identS)
			# @assert identS.modulefullname != fullname(__module__) "if $S was defined in the current module, it should have created an entry in DBS"
			localsubtypes[identS] = Vector{Symbol}()
		end
		modinfoT.methods[identS] = modinfoS.methods[identS]
	else						#local module
		@assert haskey(localsubtypes, identS)
	end
	push!(localsubtypes[identS], T)

	# add the type parameters if they exist
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
	# add the fields for the supertype to the front of list for derived type
	prepend!(ex.args[3].args, specS.fields)	

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
