################################################################################
#=
These functions help to implement the new() and super() special functions, as outlined in test/runnable_designs.jl.
=#

"""
Transforms constructor expressions by replacing `new()` and `super()` special function calls. Creates a completely new expression tree.

This function performs AST transformations on constructor function definitions to support 
the inheritance system's tuple-based field initialization approach. It validates that 
super() calls appear only in valid positions before performing transformations.

## Transformations performed:

### Abstract constructors (when isabstract=true):
- Function is renamed with "construct_" prefix
- `new(arg1, arg2, ...)` → `tuple(arg1, arg2, ...)`
- `new()` → `tuple()`
- **Requires at least one `new()` call** - throws error if no `new()` calls are found. This is to simplify the creation of constructor tuples.

The new() function is transformed to return a tuple of the field values instead of 
creating an instance. This enables the inheritance system to collect field values 
from all levels of the inheritance hierarchy before creating the final struct.
Abstract constructors must contain at least one new() call to define the structure's fields.

### Concrete constructors (when isabstract=false):
- Function name remains unchanged
- `new()` calls remain as `new()` calls (if present)
- Only super() calls are transformed
- **No requirement for `new()` calls** - can use alternative constructor patterns

### super() calls (when super_type_constructor is provided):
- `super(arg1, arg2, ...)` → `super_type_constructor(arg1, arg2, ...)...`
- `super()` → `super_type_constructor()...`

The super() function is transformed to call the specified constructor function 
and spread its tuple result. This allows constructors to invoke their parent 
constructor and include the parent's field values in their own initialization.

## Validation rules:
When `super_type_constructor` is provided, the function enforces that super() calls can only 
appear as the first argument of function calls (such as new() or constructor calls).
Invalid placements will raise an error with the message:
"super() calls can only appear as the first argument of a function (such as new() or SomeType())"

### Valid super() usage:
- `new(super(), other_args...)` ✓
- `SomeType(super(), other_args...)` ✓

### Invalid super() usage:
- `new(other_arg, super())` ✗ (not first argument)
- `super()` ✗ (standalone call)
- `some_variable = super()` ✗ (assignment)

## Examples:

### Abstract constructor with new() only:
```julia
# Input (isabstract=true):
function Apple()
	new(1.0, 3)
end

# Output:
function construct_Apple()
	tuple(1.0, 3)
end
```

### Concrete constructor with super() only:
```julia
# Input (isabstract=false, super_type_constructor=:construct_Fruit):
function Apple()
	new(super(1.0), 3)
end

# Output:
function Apple()
	new(construct_Fruit(1.0)..., 3)
end
```

### Concrete constructor without new() (valid):
```julia
# Input (isabstract=false, super_type_constructor=:construct_Fruit):
function Apple()
	Apple(super(1.0), 3)  # no new() call - this is valid for concrete constructors
end

# Output:
function Apple()
	Apple(construct_Fruit(1.0)..., 3)
end
```

### Abstract constructor with both new() and super():
```julia
# Input (isabstract=true, super_type_constructor=:construct_Food):
function Fruit(w)
	new(super(), w * 0.9, "large")
end

# Output:
function construct_Fruit(w)
	tuple(construct_Food()..., w * 0.9, "large")
end
```

### Complex constructor with statements:
```julia
# Input (isabstract=true, super_type_constructor=:construct_Fruit):
function Apple()
	do_something()
	return new(super(1.0), 3)
	do_something_else()
end

# Output:
function construct_Apple()
	do_something()
	return tuple(construct_Fruit(1.0)..., 3)
	do_something_else()
end
```

### Invalid usage (throws error):
```julia
# This will throw an error:
function Fruit(w)
	super("is confused")  # standalone super() call
end

# This will also throw an error:
function Fruit(w)
	new(:abc, super("is confused"))  # super() not in first position
end

# This will throw an error for abstract constructors:
function Apple()  # isabstract=true
	Apple(super(1.0), 3)  # no new() call
end
# Error: "new() calls are required in abstract constructors"
```

The transformed functions return tuples representing the complete field initialization 
data (for construct_ functions) or modified expressions (for regular functions) that 
will be used by the inheritance system to construct the final struct instance.
Abstract constructors must contain at least one new() call to define the structure.

# Parameters:
- `funcname`: even though it's contained in the constructor_expr, we require the function name as an argument to represent a single source of truth determined at the calling site. This can simplify the renaming of the function and make the process more robust.
- `constructor_expr`: the original expression tree of the constructor function definition
- `isabstract`: an abstract constructor will be renamed with the "construct_" prefix, and new() calls will be converted to tuple() calls. If false, the only transformation is to replace super() calls with calls to 'super_type_constructor'.
- `super_type_constructor`: Optional symbol specifying the function to call in place of super(). If not provided, super() calls are not transformed.

"""
function transform_constructor(funcname::Symbol, constructor_expr::Expr; isabstract::Bool, super_type_constructor::Union{Nothing, Symbol}=nothing)::Expr
	@assert constructor_expr.head == :function
   
   # First pass: validate super() calls are only in valid positions  
   if super_type_constructor !== nothing
	  valid_super_calls = Set{Any}()
	  
	  # Find all super() calls that are in valid positions (first argument of function calls)
	  MacroTools.postwalk(constructor_expr) do x
		 if @capture(x, f_(args__)) && length(args) >= 1
			if @capture(args[1], super(sargs__))
			   push!(valid_super_calls, args[1])
			end
		 end
		 return x
	  end
	  
	  # Check all super() calls - if any are not in valid_super_calls, they're invalid
	  MacroTools.postwalk(constructor_expr) do x
		 if @capture(x, super(args__)) && !(x in valid_super_calls)
			error("super() calls can only appear as the first argument of a function (such as new() or SomeType())")
		 end
		 return x
	  end
   end
   
   # Second pass: perform the actual transformations
	found_new = false
   res = MacroTools.postwalk(constructor_expr) do x
	  if isabstract && @capture(x, new(args__))
			found_new = true
			return :(tuple($(args...),))
	  elseif super_type_constructor !== nothing && @capture(x, super(args__))
		 construct_call = :($super_type_constructor($(args...))...)
		 return construct_call
	  else
		 return x
	  end
   end

	@assert res.head == :function

	# rename the function if it's an abstract constructor
	if isabstract
		if !found_new
			error("new() calls are required in abstract constructors")
		end
		rename_abstract_constructor!(res.args[1], funcname)
	end

	return res
end

"""
Renames the Expr(:call, original_funcname, args...) in place by prepending "construct_" to the function name. 

This function only looks down the left side (args[1]) of the expression tree to locate the function call. Experiments show that this is sufficient for the current use case.
"""
function rename_abstract_constructor!(currentexpr::Expr, original_funcname::Symbol)

	if currentexpr.head == :call && currentexpr.args[1] == original_funcname
		currentexpr.args[1] = Symbol("construct_", original_funcname)
	else
		if !isempty(currentexpr.args) && currentexpr.args[1] isa Expr
			rename_abstract_constructor!(currentexpr.args[1], original_funcname)
		else
			error("reached $currentexpr but call to $original_funcname was not found")
		end
	end

end


"""
For the given derived type, 
1. finds an available abstract constructor for the closest supertype.
2. imports the constructor function into the current module under a non-conflicting name
3. returns the name of the reference to the imported constructor function in the current module

Returns nothing if there's no Inherit.jl abstract constructor available.
"""
function locate_supertype_constructor(current_module::Module, derived_typename::Symbol)::Union{Nothing, Symbol}
	derivedtype = Base.invokelatest(getproperty, current_module, derived_typename)
	locate_constructor(current_module, supertype(derivedtype))
end

function locate_constructor(current_module::Module, basetype::DataType)::Union{Nothing, Symbol}
	consfunc = find_supertype_constructor_function(basetype)
	if consfunc === nothing
		return nothing
	end
	imported_name = Symbol(join(("__Inherit_jl", fullname(parentmodule(consfunc))..., nameof(consfunc)),'_'))
	# @show imported_name
	Core.eval(current_module, :(global $imported_name = $consfunc))
	return imported_name
end

function find_supertype_constructor_function(basetype::DataType)::Union{Nothing, Function}
	__defmodule__ = parentmodule(basetype)
	basename = nameof(basetype)

	# @show __defmodule__
	if !isdefined(__defmodule__, H_COMPILETIMEINFO) 
		# is not an Inherit.jl type and cannot have a supertype which is an Inherit.jl type
		return nothing
	end

	defmodinfo = Base.invokelatest(getproperty, __defmodule__, H_COMPILETIMEINFO)
	# @show defmodinfo
	if !haskey(defmodinfo.consdefs, basename) 
		@debug "$__defmodule__ is used by Inherit but $basename has no entry in consdefs; not declared as @abstractbase?"
		return nothing
	end

	if isempty(defmodinfo.consdefs[basename])
		# no constructor definitions for this type, look in supertype
		return find_supertype_constructor_function(supertype(basetype))
	end

	# defined and recorded
	constructor_name = Symbol("construct_", basename)
	@assert isdefined(__defmodule__, constructor_name)
	return Base.invokelatest(getproperty, __defmodule__, constructor_name)
end

"""
'T' the derived type, 'S' the supertype.

Finds all constructor definitions in the given lines and transforms them in place.
"""
function find_and_transform_constructors!(lines::AbstractVector{<:Any}, T::Symbol, S::Union{Symbol, Expr},current_module::Module)
	objS = Core.eval(current_module, S)		

	for (i, line) in enumerate(lines)
		if isexpr(line, :function)
			if !@capture(line, (function funcname_(__) body__ end) | (function funcname_(__)::__ body__ end))
				errorstr = "Cannot recognize $line as a constructor. It must look like `function funcname(...) ... end`"
				return :(throw(ImplementError($errorstr)))
			end
			is_constructor = funcname == T
			if is_constructor
				# Process constructor definition
				imported_cons_name=locate_constructor(current_module, objS)		
				transformed_expr = transform_constructor(funcname, line;
					isabstract=false, 
					super_type_constructor=imported_cons_name)
				
				# we don't want to eval here, T hasn't been defined yet. We just modify 'lines' in place.
				lines[i] = transformed_expr
		
				# since we're in a concrete class, in theory we don't need to store anything (and in fact we may not have setup CompileTimeInfo for the module) for use by derived types.
			end			
		end #if isexpr(line, :function)
	end #for (i, line) in enumerate(lines)
end #find_and_transform_constructors!