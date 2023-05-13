"""
Inherit.jl let's the user inherit fields and interface definitions from a supertype. There are two macros which provide abstract templates for concrete types: @abstractbase which declares an abstract supertype with inheritable fields and required method definitions, and @interface which declares a container rather than supertype, while providing the same inheritance features. The @implement macro creates the concrete type that implements either or both of these templates. While a concrete type may  implement only one @abstractbase, multiple @interface's may be implemented.
	
We have steered away from using the term "traits" to avoid confusion with extensible [Holy traits](https://invenia.github.io/blog/2019/11/06/julialang-features-part-2/) widely used in Julia libraries. While @interface's can be multiplely inherited, they cannot be added to an existing concrete type from another package. 

# Limitations
Concrete type must be defined in the same module as the method definitions specific t.

Short form function definitions such as `f() = nothing` are not supported for method declaration; use the long form `function f() end` instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.

Just like Julia types, definitions should be given in the order of their dependencies. While out-of-order code can work in some circumstances, we don't test for them. Within a given type, field and method definitions must be unique.

Inherit.jl has no special knowledge about constructors (inner or otherwise). They're treated like normal functions.

The package's macros must be used at the toplevel of a module. @abstractbase relies on world age to advance in order to detect a "real" method was defined (to differentiate the case where the method definition has identical signature as interface specification). 

If you cannot return to toplevel (e.g. being wrapped in a @testset macro), a work around is to modify the signature slightly but retain the call paths that you require.

Currently we only handle long form interface definitions such as `function f() end`.

TODO: multiple levels of interface (not hard)
TODO: multiple interfaces (may be hard)
TODO: what about parametric types?

A method's signature given *only* by its positional arguments is unique. If you define a method with the same positional arguments but different keyword arguments from a previously defined method, it will overwrite the previous method. Keyword arguments simply do not particular in method dispatch.

A parametric type signature can be supertype of abstract type signature
	Tuple{typeof(f), Real} <: Tuple{typeof(f), T} where T<:Number

`typeof(f).name.mt` grows for each evaluation of method definition, even if it overwrites a previous definition. It is not the same as `methods(f)`
	

"""
module Inherit
export @abstractbase, @implement, @interface, @postinit, @test_nothrows, InterfaceError, ImplementError, SettingsError, (<--), setglobalreportlevel, setreportlevel, ThrowError, ShowMessage, DisableInit

using MacroTools, Logging
import Test:@test

#module property name of the dict mapping from abstract base type names to expressions for fields of the base type
const H_FIELDS::Symbol = :__Inherit_jl_FIELDS
#module property name of the dict mapping type identifier to method interfaces. Unlike DB_FIELDS, this one can contain interfaces defined in a foreign module.
const H_METHODS::Symbol = :__Inherit_jl_METHODS
#module property name of the dict mapping type identifier to (nonqualified) subtype names
const H_SUBTYPES::Symbol = :__Inherit_jl_SUBTYPES
#function names we auto imported, so we don't repeat warning messages
const H_IMPORTED::Symbol = :__Inherit_jl_IMPORTED

#super type identifier
TypeIdentifier = @NamedTuple{
	modulefullname::Tuple, 	#module where the supertype was originally defined
	basename::Symbol}			#name of the supertype
MethodDeclaration = @NamedTuple{
	defmodulename::Tuple, 	#module where the declaration was originally defined. helps with line reduction
	defbasename::Symbol,		#base type name where the declaration was originally defined. helps with line reduction
	line::Expr, 				#the original statement AST
	linecomment::Union{Nothing, String, Expr},		#String or Expr(:string ...) that documents the line
	sig::Type{<:Tuple}}		#the original sig evaluated in original module

struct InterfaceError <: Exception
	msg::String
end
struct ImplementError <: Exception
	msg::String
end
struct SettingsError <: Exception
	msg::String
end

include("reportlevel.jl")
include("utils.jl")

function setup_module_db(mod::Module)
	### only done once on first use of @abstractbase or @implement in a module
	if !isdefined(mod, H_FIELDS)
		setproperty!(mod, H_FIELDS, Dict{
			Symbol, 											#abstract base type (local only)
			Vector{Expr}}())								#list of field definition expressions
		setproperty!(mod, H_METHODS, Dict{
			TypeIdentifier, 								#abstract base type (local or foreign)
			Vector{MethodDeclaration}}())				#list of method declarations required by the base type; this includes local as well as inherited definitions
		setproperty!(mod, H_SUBTYPES, Dict{
			TypeIdentifier, 								#supertype (local or foreign) identifier
			Vector{Symbol}}())							#local subtype name
		setproperty!(mod, H_IMPORTED, Set{
			TypeIdentifier}())							#(modulefullname,funcname) pairs that have been auto imported into the current module
		

		me = getmoduleentry(mod)
		if me.rl != DisableInit
			### setup the module init to check for implementations after module is fully loaded
			initexp = create_module__init__()
			# dump(initexp; maxdepth=16)
			# println(initexp)
			mod.eval(initexp)		#NOTE: do not do rmlines or this eval can have problems
			me.init_created = true
		end
	end
end

function process_supertype(currentmod::Module, S::Union{Symbol, Expr})
	objS = currentmod.eval(S)		
	moduleS = objS.name.module
	nameS = objS.name.name			
	if !isdefined(moduleS, H_FIELDS)
		error("no @abstractbase's have been declared in $moduleS")
	end	
	U_DBF = getproperty(moduleS, H_FIELDS)		#either foreign or local DBF
	if !haskey(U_DBF, nameS)
		error("supertype $nameS not found in $moduleS -- It needs to have been declared with @abstractbase")
	end
	identS = TypeIdentifier((fullname(moduleS), nameS))
	U_DBM = getproperty(moduleS, H_METHODS)
	@assert haskey(U_DBM, identS)
	
	### import all the foreign function declarations into the current module. Any methods we define will live with the foreign module's functions; they not not create our own function.
	DBI = getproperty(currentmod, H_IMPORTED)
	currentfullname = fullname(currentmod)
	for decl in U_DBM[identS]
		if decl.defmodulename == currentfullname continue end	#no need to import

		funcname = getfuncname(decl)
		identF = TypeIdentifier((decl.defmodulename, funcname))

		if !isdefined(currentmod, funcname)
			expr = to_import_expr(funcname, decl.defmodulename...)
			# currentmod.eval(:(export $funcname))	#NOTE: export must come before the symbol import, in order to work. I think we may not actually want this. Allow export lists to be explicit.
			currentmod.eval(expr)
			push!(DBI, identF)
			@debug "auto imported with `$expr`"
		elseif identF ∉ DBI
			@warn "$(nameof(currentmod)) already has a symbol `$funcname`. To implement $(decl.line) you should write the function name as `$(tostring(decl.defmodulename, funcname))`"
		end
	end
	
	identS, U_DBF, U_DBM
end

"
TODO: evaluate in a temporary module
TODO: support mutable types
"
macro abstractbase(ex)
	setup_module_db(__module__)

	ex = longdef(ex)		#normalizes function definition to long form
	T = S = nothing
	if @capture(ex, struct T_Symbol<:S_ lines__ end)
	elseif @capture(ex, struct T_Symbol lines__ end)
	else 
		throw(InterfaceError("Cannot parse the following as a struct type:\n $ex"))
	end
	# @show T, S
	#eval right away so the type will be available in function definitions
	if S === nothing
		__module__.eval(:(abstract type $T end))
	else
		__module__.eval(:(abstract type $T <: $S end))
	end
	MOD = __module__.eval(:(fullname(parentmodule($T))))		

	DBF = getproperty(__module__, H_FIELDS)
	DBM = getproperty(__module__, H_METHODS)
	DBS = getproperty(__module__, H_SUBTYPES)

	#a type definition completely overwrites previous definitions, method, fields, subtypes are all reset for the type.
	if T ∈ keys(DBF)
		@warn "overwriting previous definition of $T in $__module__"
	end
	identT = TypeIdentifier((MOD,T))

	function reset_type()
		DBF[T] = Vector{Expr}()
		DBM[identT] = Vector{MethodDeclaration}()
		DBS[identT] = Vector{Symbol}()
		if S !== nothing		#copy fields and methods from the super type to the subtype 
			identS, U_DBF, U_DBM = process_supertype(__module__, S)

			#we bring over fields and method declarations from S and add it to T
			append!(DBF[T], U_DBF[identS.basename])
			append!(DBM[identT], U_DBM[identS]) #but the original `line` may still be referring to the original module
		end
	end
	reset_type()

	comment = nothing
	for line in lines
		if @capture(line, x_String_string)
			comment = x				#save comment to apply to next line. Note that we take a slight cheat by ignoring line number nodes. Unlike proper Julia, comments will apply even across blank lines.
		else
			if isexpr(line, :function)
				### the interface requires a method that is supertype of this to be defined --- EXCEPT that occurences of T can be replaced with a subtype of T --- with later world age than this.
				f = __module__.eval(line)		#evaluated in calling module without hygiene pass
				m = last_method_def(f)
				@debug "interface specified by $T: $(m.sig), age $(m.primary_world)"

				# duplicate fields will be detected by the implementing struct. duplicate methods are detected by us.
				if !all(p->p.sig != m.sig, DBM[identT])
					reset_type()	#clears everything we've seen so far about the type, so it isn't misused? how necessary is this?
					errorstr = "duplicate method definition at $(__source__.file):$(__source__.line)"
					return :(throw(InterfaceError($errorstr)))
				end

				#NOTE: evaluating `@doc comment $(nameof(f))` here will only have a temporary effect. To persist documentation it must be done at the module __init__
				push!(DBM[identT], MethodDeclaration((MOD, T, line, comment, m.sig)))
				comment = nothing
				Base.delete_method(m)   # `WARNING: method deletion during Module precompile may lead to undefined behavior` This warning shows up even when deleting in module __init__.

			elseif isexpr(line, :(::))
				push!(DBF[T], line)
			elseif line isa Symbol 		#Any is implied, normalize it to the same expression format as typed field
				line = :($line::Any)
				push!(DBF[T], line)
			else
				@warn "ignoring unrecognized expression: $line"
			end

			if comment !== nothing		#comment was not used
				@warn "ignoring string expression: $comment"
				comment = nothing		
			end
		end	#if @capture...
	end	#for line...

	# to_qualified_expr(MOD..., T)	#evaluates to the abstract type we just created, which allows Base.@__doc__ to work. Note the fully qualified name is needed to evaluate type T, for some reason.
	if S === nothing
		:(abstract type $T end)
	else
		:(abstract type $T <: $S end)
	end

end 	#end @abstractbase

function create_module__init__()::Expr
	# TODO: this was hard won knowledge; implement it in some function?
	# ### Find whether Inherit module is in Debug logging level. If it is, error messages will be printed in place of exceptions, because exceptions cannot be caught from module __init__ 
	# init_throwsexception = let
	# 	log_data = Base.CoreLogging.process_logmsg_exs(Inherit, nothing, nothing, Debug, "hello")
	# 	logger = Base.CoreLogging.current_logger_for_env(Debug, log_data._group, log_data._module)

	# 	# @show @macroexpand @debug "hello there"
	# 	# @show state = Base.CoreLogging.current_logstate()  This doesn't return the correct logger for Inherit
	# 	logger === nothing || !Logging.shouldlog(logger, Debug, Inherit, :Inherit, nothing)
	# end
	# if (!init_throwsexception)
	# 	@warn "any exceptions will show as error messages only, to allow tests to complete" init_throwsexception
	# end
	
	qnodeM = QuoteNode(H_METHODS)
	qnodeS = QuoteNode(H_SUBTYPES)

	"
	In the user module's init, we need to throw exceptions directly, since there's no eval on the return value.
	NOTE that only the quoted expression has access to the correct @__MODULE__. Any utility functions of Inherit.jl must receive this as a parameter, instead of invoking @__MODULE__ directly.
	"
	quote function __init__()
		if Inherit.isprecompiling() return end		#Can't use eval when precompiling, which "closes" a package. If Pkg2 loads precompiled Pkg1, Pkg1.__init__() will fire, which fails when trying to eval into closed Pkg1.

		modentry = Inherit.getmoduleentry(@__MODULE__)
		n_supertypes = n_subtypes = n_signatures = n_errors = 0

		function handle_error(errorstr::String)
			n_errors += 1
			if modentry.rl == Inherit.ThrowError
				throw(ImplementError(errorstr))
			else
				@assert modentry.rl == Inherit.ShowMessage
				@error errorstr
			end
		end

		if isdefined(@__MODULE__, $qnodeM)
			DBM = getproperty(@__MODULE__, $qnodeM)
			DBS = getproperty(@__MODULE__, $qnodeS)
			LOCALMOD = fullname(@__MODULE__)
			LM_HANDLE  = Symbol(:__Inherit_jl_, LOCALMOD[end])
			for (identS, decls) ∈ DBM
				n_supertypes += 1
				# __supertypemod__ = Inherit.getmodule(identS.modulefullname)
				# isforeign = __supertypemod__ != @__MODULE__
				# if isforeign	#skips installing a handle if local module, so we don't litter a module with handles unnecessarily.
				# 	setproperty!(__supertypemod__, LM_HANDLE, @__MODULE__)
				# end
				SUBTYPES = DBS[identS]
				n_subtypes += length(SUBTYPES)
				n_signatures += length(decls)

				if isempty(SUBTYPES)	
					@debug "$(Inherit.tostring(identS)) has no subtypes; not requiring method implementations"
					@goto all_types_satisfy_sig 
				end

				@debug "Inherit.jl requires interface definitions defined in base type $(Inherit.tostring(identS)) to be satisfied"
				for decl in decls							# required sigs
					### get method table for function defined in the current, implementing module (not the declaration module)
					funcname = Inherit.getfuncname(decl)
					__defmodule__ = Inherit.getmodule(@__MODULE__, decl.defmodulename)
					func = nothing
					mt = nothing
					if isdefined(__defmodule__, funcname)
						func = getproperty(__defmodule__, funcname)
						# func = (__defmodule__).eval(funcname)
						mt = methods(func)
						# @show mt
					end
					if mt === nothing || isempty(mt)
						errorstr = "$(nameof(__defmodule__)) does not define a method for `$funcname`, which is required by:\n$(decl.line)"
						handle_error(errorstr)
						continue
					end

					### make sure the defmodule can access the implementing type
					isforeign = __defmodule__ != @__MODULE__
					if isforeign		#skips installing a handle if local module, so we don't litter a module with handles unnecessarily.
						setproperty!(__defmodule__, LM_HANDLE, @__MODULE__)
					elseif decl.linecomment !== nothing	
						#for local module, set the @doc for method declarations
						@debug "documenting `$funcname` with `$(decl.linecomment)`"
						expr = :(@doc $(decl.linecomment) $funcname)
						(@__MODULE__).eval(expr)
					end

					@debug "$(identS.basename) requires $(decl.sig) for each subtype"
					for subtype in SUBTYPES		# each subtype must satisfy each interface signature
						# f = sig.parameters[1].instance   	#the function is still available even if all methods have been deleted
						# mt = methods(f) 		
						type_satisfied = false

						# for each subtype it only needs to satisfy the concrete sig, where each occurrence of type T has been replaced with type subtype
						reducedline = Inherit.reducetype(decl.line, 
							decl.defmodulename, decl.defbasename, 
							isforeign ? (LM_HANDLE,) : LOCALMOD, subtype)
						
						###we rename the reduced function before evaluating to get the signature, in order to prevent overwriting existing implementing method
						reducedline = Inherit.privatize_funcname(reducedline)
						f = __defmodule__.eval(reducedline) 
						reducedmethod = Inherit.last_method_def(f)
						#restore the functype signature from the original declaration
						reducedsig = Inherit.set_sig_functype(__defmodule__, reducedmethod.sig, decl.sig.types[1])
						#this is safe to delete because it's on the renamed function
						Base.delete_method(reducedmethod)						

						for m in mt				#methods implemented on function of required sig
							if decl.sig <: m.sig	# being a supersig in the unmodified version satisfies all subtypes. 
								type_satisfied = true
								@debug "all subtypes have been satisfied by $(m.sig)"
								@goto all_types_satisfy_sig
							elseif reducedsig <: m.sig
								@debug "subtype $(Inherit.tostring(LOCALMOD, subtype)) satisfied by $(m.sig)"
								type_satisfied = true
							end							
						end
						if !type_satisfied
							errorstr = "subtype $(Inherit.tostring(LOCALMOD, subtype)) missing $reducedsig declared as:\n$(decl.line)"
							handle_error(errorstr)
						end
					end	#end subtypes
				end
				@label all_types_satisfy_sig
			end
			@info """Inherit.jl: processed $(join(LOCALMOD, '.')) with $(Inherit.singular_or_plural(n_supertypes, "supertype")) having $(Inherit.singular_or_plural(n_signatures, "method requirement")). $(Inherit.singular_or_plural(n_subtypes, "subtype was", "subtypes were")) checked with $(Inherit.singular_or_plural(n_errors, "missing method"))."""
		else
			@debug "I don't require any definitions"
		end		
		# do postinit
		for f in modentry.postinit
			f()
		end
	end end 	#end quote
end

"
Executed after Inherit.jl verfies interfaces. You may have any number of @postinit blocks; they will execute in the sequence order in which they're defined.
"
macro postinit(ex)
	@assert MacroTools.isdef(ex) "function definition expected"
	modentry = Inherit.getmoduleentry(__module__)
	if modentry.rl == DisableInit
		return :(throw(SettingsError("module is set to DisableInit. @postinit requires ThrowError or ShowMessage setting.")))
	else
		push!(modentry.postinit, __module__.eval(ex))
	end
end

"
Method declarations may come from a foreign module, in which case, method implementations must belong to functions in that foreign module. If there's no name clash, the foreign modules's function is automatically imported into the implementing module (i.e. your current module). If there is a name clash, you must qualify the method implementation with the foreign module's name.
"
macro implement(ex)
	setup_module_db(__module__)

	if @capture(ex, struct T_Symbol<:S_ fields__ end)
	else
		errorstr = "Cannot parse the following as a struct subtype:\n $ex"
		return :(throw(ImplementError($errorstr)))
	end
	# dump(S; maxdepth=16)

	### evaluate the supertype expression so we can get the correct module
	identS, U_DBF, U_DBM = process_supertype(__module__, S)

	# recording as subtype in the local module's dict. this activates any method requirements for the supertype
	DBS = getproperty(__module__, H_SUBTYPES)
	DBM = getproperty(__module__, H_METHODS)

	if U_DBM != DBM		#foreign module
		if !haskey(DBS, identS)
			# @assert identS.modulefullname != fullname(__module__) "if $S was defined in the current module, it should have created an entry in DBS"
			DBS[identS] = Vector{Symbol}()
		end
		DBM[identS] = U_DBM[identS]
	else						#local module
		@assert haskey(DBS, identS)
	end
	push!(DBS[identS], T)

	# if moduleS === __module__			# super type is from same module
	# 	ident = TypeIdentifier((MOD, nameS))
	# 	@assert haskey(DBS, ident)		# should have been created when super type was declared
	# 	push!(DBS[ident], T)
	# else
	# 	# copy super type's method signatures from foreign module into this module, so they can be verified on module init
	# 	FOREIGN_DBM = getproperty(moduleS, H_METHODS)
	# 	FOREIGN_MOD = fullname(moduleS)
	# 	DBM = getproperty(__module__, H_METHODS)
	# 	ident = TypeIdentifier((FOREIGN_MOD, nameS))
	# 	DBM[ident] = FOREIGN_DBM[ident]

	# 	# add subtype under imported name
	# 	if !haskey(DBS, ident)
	# 		DBS[ident] = Vector{Symbol}()
	# 	end
	# 	push!(DBS[ident], T)
	# end

	# add the fields for the supertype to the front of list for derived type
	prepend!(ex.args[3].args, U_DBF[identS.basename])	

	esc(ex)		#hygiene pass will resolve ex to the Inherit module if not escaped
end	#end @implement


"
An @abstractbase follows Julia's type hierarchy; a concrete type may only implement one abstractbase. A @interface is similar in some ways to Holy traits; a type may implement multiple interfaces in addition to its abstractbase. A interface can span type hierarchies, but it may only be used to inherit fields and function definition requirements. It cannot be used as a container element or object type (while carrying the behavior of interfaces).

Can recreate the struct parameterized by the interface, this allows dispatch only on type, or on both type and interface. Basically, store the list of interfaces in the type parameters, and create default constructors that don't require the interface parameters.
"
macro interface(ex)
	esc(ex)
end

"opposite of @test_throws"
macro test_nothrows(exp, args...)
	try
		__module__.eval(exp)
		:(@test true $(args...))
	catch e
		showerror(stderr, e, catch_backtrace())
		:(@test false $(args...))
	end
end

function (<--)(a ,b)
	@error "$a does not implement interface $b"
	false
end

end # module Inherit
