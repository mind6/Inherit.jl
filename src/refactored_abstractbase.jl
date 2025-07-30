
"""
	parse_abstractbase_type(ex)

Parse the type definition expression for the @abstractbase macro.
Returns a tuple of (type_name, supertype, type_parameters, ismutable, body_lines).

# Side effects:
- None, this is a pure parsing function
"""
function parse_abstractbase_type(ex)
	ex = MacroTools.longdef(ex) # Normalize function definitions to long form

	# Determine the structure of the type expression
	ismutable = false
	T = S = P = nothing
	lines = nothing
	
	if @capture(ex, struct T_Symbol<:S_ lines__ end)
		ismutable = false
	elseif @capture(ex, struct T_Symbol lines__ end)
		ismutable = false
	elseif @capture(ex, struct T_Symbol{P__} lines__ end)
		ismutable = false
	elseif @capture(ex, struct T_Symbol{P__}<:S_ lines__ end)
		ismutable = false
	elseif @capture(ex, mutable struct T_Symbol<:S_ lines__ end)
		ismutable = true
	elseif @capture(ex, mutable struct T_Symbol lines__ end)
		ismutable = true
	elseif @capture(ex, mutable struct T_Symbol{P__} lines__ end)
		ismutable = true
	elseif @capture(ex, mutable struct T_Symbol{P__}<:S_ lines__ end)
		ismutable = true
	else 
		throw(InterfaceError("Cannot parse the following as a struct type:\n $ex"))
	end
	
	return (T, S, P, ismutable, lines)
end

"""
	define_abstract_type(module_ref, type_name, supertype)

Generate an abstract type definition expression and evaluate it in the given module.
Returns the evaluated abstract type expression.

# Side effects:
- Defines a new abstract type in the module
"""
function define_abstract_type(module_ref, type_name, supertype)
	# Create abstract type expression
	if supertype === nothing
		ret_expr = :(abstract type $type_name end)
	else
		ret_expr = :(abstract type $type_name <: $supertype end)
	end
	
	# Evaluate the expression to make the type available
	Core.eval(module_ref, ret_expr)
	
	return ret_expr
end

"""
	initialize_type_metadata(current_module, type_name, ismutable)

Initialize or reset the metadata for a type in the inheritance database.
Returns the TypeIdentifier for the type.

# Side effects:
- Creates or resets entries in the module's inheritance database for the type
- Warns if overwriting a previous definition
"""
function initialize_type_metadata(current_module::Module, type_name::Symbol, ismutable::Bool)
	module_fullname = fullname(current_module)
	modinfo = getproperty(current_module, H_COMPILETIMEINFO)

	# Warn if overwriting
	if type_name ∈ keys(modinfo.localtypespec)
		@warn "overwriting previous definition of $type_name in $current_module"
	end
	
	# Create type identifier
	identT = TypeIdentifier((module_fullname, type_name))
	
	# Create initial empty metadata
	modinfo.localtypespec[type_name] = TypeSpec((
		ismutable,
		Vector{SymbolOrExpr}(), # Start with empty array for type params
		Vector{Expr}()))        # Start with empty array for fields
		
	modinfo.methods[identT] = Vector{MethodDeclaration}()
	modinfo.constructor_definitions[identT] = Vector{ConstructorDefinition}()
	modinfo.subtypes[identT] = Vector{Symbol}()
	
	return identT
end

"""
	inherit_supertype_metadata(current_module, type_name, supertype)

Process the supertype and inherit its fields and methods.
Returns an error expression if there's an issue with inheritance.

# Side effects:
- Updates type specification with inherited fields and type parameters
- Updates method database with inherited method declarations
- Imports functions from foreign modules if needed
"""
function inherit_supertype_metadata(current_module::Module, type_name::Symbol, supertype::Union{Nothing,Symbol, Expr})::Union{Nothing, Expr}
	if supertype === nothing
		return nothing
	end
	
	# Process the supertype to get its metadata
	identS, modinfoS = process_supertype(current_module, supertype)
	
	if identS === nothing
		# Not an @abstractbase, nothing to inherit
		return nothing
	end
	modinfoT = getproperty(current_module, H_COMPILETIMEINFO)
	
	# Check mutability compatibility
	specS = modinfoS.localtypespec[identS.basename]
	specT = modinfoT.localtypespec[type_name]
	if specT.ismutable != specS.ismutable
		errorstr = "mutability of $supertype is $(specS.ismutable) but that of $type_name is $(specT.ismutable)"
		return :(throw(InterfaceError($errorstr)))
	end
	
	# Inherit type parameters (first) and fields
	append!(specT.typeparams, specS.typeparams)
	append!(specT.fields, specS.fields)
	
	# Type identifier for the current type
	identT = TypeIdentifier((fullname(current_module), type_name))
	
	# Inherit method declarations
	append!(modinfoT.methods[identT], modinfoS.methods[identS])
	
	return nothing
end

"""
	process_field_definition(type_spec, line)

Process a field definition and add it to the type specification.

# Side effects:
- Adds field to the type's field list in the database
"""
function process_field_definition(type_spec, line)
	if isexpr(line, :(::), :const)
		push!(type_spec.fields, line)
	elseif line isa Symbol
		# Any is implied, convert to expression
		line = :($line::Any)
		push!(type_spec.fields, line)
	else
		@warn "ignoring unrecognized expression: $line"
	end
end

"""
	process_method_declaration(current_module, type_name, ident, line, comment)

Process a method declaration in the type body.

# Side effects:
- Declares function prototype in the current module
- Adds method declaration to the database
"""
function process_method_declaration(current_module, type_name, ident, line, comment)
	if !@capture(line, (function funcname_(__) body__ end) | (function funcname_(__)::__ body__ end))
		errorstr = "Cannot recognize $line as either a constructor or a valid prototype definition."
		return :(throw(InterfaceError($errorstr)))
	end
	
	# Get method body stripped of line number nodes
	body = MacroTools.striplines(body)
	
	# Check if this is a constructor (function name matches type name)
	is_constructor = funcname == type_name
	
	modinfo = getproperty(current_module, H_COMPILETIMEINFO)
	module_fullname = fullname(current_module)
	
	if is_constructor
		# Process constructor definition
		super_type_constructor_name = get_supertype_constructor_name(current_module, type_name)
		transformed_constructor = transform_new_calls(line, super_type_constructor_name)
		construct_function = generate_construct_function(transformed_constructor)
		
		# Store the constructor prototype for later implementation
		push!(modinfo.constructor_definitions[ident], ConstructorDefinition(module_fullname, type_name, line, construct_function, comment))
	elseif body === nothing || isempty(body)
		# Regular method declaration -  declare the function without methods in the current_module
		Core.eval(current_module, :(@doc $comment function $(funcname) end)) 	# document the function in the current_module
		f = getproperty(current_module, funcname)
		functype = typeof(f)
		
		shadowmodule = createshadowmodule(current_module)
		shadowsig = make_function_signature(shadowmodule, functype, line)

		# Store method declaration in the database
		push!(modinfo.methods[ident], MethodDeclaration(module_fullname, type_name, line, comment, funcname, functype, shadowsig))
	else
		errorstr = "Cannot recognize $line as a valid prototype definition. It must look like `function funcname(...) end` without a body."
		return :(throw(InterfaceError($errorstr)))
	end
	
	return nothing
end

"""
	process_type_body(current_module, type_name, lines)

Process all lines in the abstract type body, handling method declarations,
field definitions, and documentation comments.

# Side effects:
- Adds field definitions to the type specification
- Processes and stores method declarations
- Processes constructor definitions
"""
function process_type_body(current_module, type_name, lines)
	# Get the TypeIdentifier for the current type
	module_fullname = fullname(current_module)
	identT = TypeIdentifier((module_fullname, type_name))
	
	modinfo = getproperty(current_module, H_COMPILETIMEINFO)
	
	# Process each line in the type definition
	comment = nothing
	for line in lines
		if @capture(line, x_String_string)
			# Save comment to apply to next line
			comment = x
		else
			# Process methods and fields
			if isexpr(line, :function)
				result = process_method_declaration(current_module, type_name, identT, line, comment)
				if result !== nothing
					return result
				end
			else
				# Process field definition
				process_field_definition(modinfo.localtypespec[type_name], line)
			end
			
			# Reset comment if it wasn't used
			if comment !== nothing
				# @warn "ignoring string expression: $comment"
				comment = nothing
			end
		end
	end
	
	return nothing
end

"""
	add_type_parameters(current_module, type_name, type_params)

Add type parameters to a type's metadata after inheritance has been processed.

# Side effects:
- Appends type parameters to the type's parameter list in the database
"""
function add_type_parameters(current_module, type_name, type_params)
	if type_params === nothing
		return
	end
	
	modinfo = getproperty(current_module, H_COMPILETIMEINFO)
	
	# Add the type parameters to the end of the list (after any inherited params)
	append!(modinfo.localtypespec[type_name].typeparams, type_params)
end

# Main abstractbase macro implementation
macro abstractbase(ex)
	# 1. Initialize module database
	setup_module_db(__module__)
	
	# 2. Parse the type definition
	T, S, P, ismutable, lines = parse_abstractbase_type(ex)
	
	# 3. Define the abstract type in the module
	ret_expr = define_abstract_type(__module__, T, S)
	
	# 4. Initialize type metadata in the database (without type parameters yet)
	initialize_type_metadata(__module__, T, ismutable)
	
	# 5. Inherit from supertype if one exists
	ret = inherit_supertype_metadata(__module__, T, S)
	if ret !== nothing
		return ret
	end
	
	# 6. Add our own type parameters AFTER inheriting from supertype
	add_type_parameters(__module__, T, P)
	
	# 7. Process the body of the type definition
	ret = process_type_body(__module__, T, lines)
	if ret !== nothing
		return ret
	end
	
	# 8. Return the abstract type expression (escaped for hygiene)
	esc(ret_expr)
end
