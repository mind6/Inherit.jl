#=
These functions help to implement the new() and super() special functions, as outlined in test/runnable_designs.jl.
=#

# Transform new calls in constructors
function transform_new_calls(constructor_expr)
    # Replace new(args...) with (args...)
    MacroTools.postwalk(constructor_expr) do x
        if @capture(x, new(args__))
            return :(return ($(args...),))
        else
            return x
        end
    end
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
Transform super() calls in constructor bodies to calls to the superclass constructor.
Replaces super() with construct_Supertype()... where Supertype is the superclass name.
"""
function transform_super_calls(expr, supertype_name)
    if supertype_name === nothing
        # If no supertype, leave super as is (may cause error later)
        return expr
    end
    
    MacroTools.postwalk(expr) do x
        if @capture(x, super(args__))
            construct_name = Symbol("construct_", supertype_name)
            if isempty(args)
                # super() -> construct_Supertype()...
                :($construct_name()...)
            else
                # super(a, b) -> construct_Supertype(a, b)
                :($construct_name($(args...)))
            end
        else
            x
        end
    end
end