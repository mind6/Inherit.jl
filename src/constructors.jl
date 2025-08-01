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

The new() function is transformed to return a tuple of the field values instead of 
creating an instance. This enables the inheritance system to collect field values 
from all levels of the inheritance hierarchy before creating the final struct.

### Concrete constructors (when isabstract=false):
- Function name remains unchanged
- `new()` calls remain as `new()` calls
- Only super() calls are transformed

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
```

The transformed functions return tuples representing the complete field initialization 
data (for construct_ functions) or modified expressions (for regular functions) that 
will be used by the inheritance system to construct the final struct instance.
Functions with no new() calls remain unchanged.

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
   res = MacroTools.postwalk(constructor_expr) do x
      if isabstract && @capture(x, new(args__))
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
Get the constructor function name for the closest immediate supertype of the given type which has a constructor.
Returns nothing if there's no supertype or no constructor available.
"""
function get_supertype_constructor_name(current_module::Module, current_type_name::Symbol)
    modinfo = getproperty(current_module, H_COMPILETIMEINFO)
    
    if !haskey(modinfo.localtypespec, current_type_name)
        return nothing
    end    
   
    # TODO: Implement actual supertype resolution logic
    # This should:
    # 1. Find the applicable supertype of current_type_name, which is a TypeIdentifier
    # 2. Return the appropriate construct_SuperTypeName symbol
    # 3. Handle cross-module cases properly
    return nothing  # placeholder
end

