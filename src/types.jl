
SymbolOrExpr = Union{Symbol, Expr}

"Uniquely identifies a supertype."
TypeIdentifier = @NamedTuple{
	modulefullname::Tuple, 	#module where the supertype was originally defined
	basename::Symbol}			#name of the supertype

TypeSpec = @NamedTuple{
	ismutable::Bool,			#whether or not the fields of this type are mutable
	typeparams::Vector{SymbolOrExpr},  #expressions that define the type parameters, including those inherited from supertype
	fields::Vector{Expr}		#expressions that define the type's fields (including those inherited from supertype)	
}

struct MethodDeclaration 
	defident::TypeIdentifier	#the identifier of the supertype where the declaration was originally defined
	line::Expr	 				#the original statement AST
	linecomment::Union{Nothing, String, Expr}		#String or Expr(:string ...) that documents the line
	funcname::Symbol			#name of function. must be determined at type definition time. It cannot be extracted from sig because it may be empty until module __init__.
	functype::DataType			#the original functype evaluated in original module. This is key to signature checking, and it results from the only evaluation we make into a non-temporary module.
	sig::Type{<:Tuple}		#the original sig evaluated in original module
end

struct ConstructorDefinition 
	defident::TypeIdentifier	#the identifier of the supertype where the declaration was originally defined
	original_expr::Expr
	transformed_expr::Expr
	imported_cons_name::Union{Nothing, Symbol}
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


"""
There is one instance for each module which uses Inherit.jl. It is built up when @abstractbase and @implement macros execute at compile time. 

It must contain strings and expressions that describe the types, but not runtime instances themselves. It may contain compile time state and evaluated function objects. These function objects can be called during module __init__, as per PkgTest4.jl


"""
@kwdef struct CompiletimeModuleInfo
	# abstract base type (defined in local module only) => flags and fields for this type
	localtypespec::Dict{Symbol, TypeSpec} = Dict{Symbol, TypeSpec}()

	# abstract base type (defined in local module only) => list of constructor definitions
	consdefs::Dict{Symbol, Vector{ConstructorDefinition}} = Dict{Symbol, Vector{ConstructorDefinition}}()

	# abstract base type (local or foreign) => list of required methods (including those inherited from supertypes)
	method_decls::Dict{TypeIdentifier, Vector{MethodDeclaration}} = Dict{TypeIdentifier, Vector{MethodDeclaration}}()


	# abstract base type (local or foreign) => list of local subtypes
	subtypes::Dict{TypeIdentifier, Vector{Symbol}} = Dict{TypeIdentifier, Vector{Symbol}}()

	# (modulefullname,funcname) pairs that have been auto imported
	imported::Set{TypeIdentifier} = Set{TypeIdentifier}()

end