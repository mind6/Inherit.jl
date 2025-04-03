#=
These functions help to implement the @new and @super macros, as outlined in test/runnable_designs.jl.
=#

# Transform @new calls in constructors
function transform_new_calls(constructor_expr)
   # Replace @new(args...) with (args...)
   MacroTools.postwalk(constructor_expr) do x
       if @capture(x, @new(args__))
           return :(return ($(args...),))
       else
           return x
       end
   end
end

# Generate construct_TypeName function from constructor
function generate_construct_function(constructor_expr)
   constructor_expr = constructor_expr.args[2]
   # Extract function arguments and body
   type_name = constructor_expr.args[1].args[1]
   func_args = constructor_expr.args[1].args[2:end]
   func_body = constructor_expr.args[2]
   
   # Create the construct_TypeName function
   :(function $(Symbol("construct_", type_name))($(func_args...))::Tuple
       $func_body
   end)
end
