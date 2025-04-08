using Test
using MacroTools
include("../src/constructors.jl")

function show_expr(expr)
   dump(expr)
end

macro my_macro(expr)
   show_expr(expr)
end

@my_macro function my_func()
    return 1+2
end

show_expr(:(
    function my_func()
        return 1+2
    end
))
show_expr(quote
    function my_func()
        return 1+2
    end
end)



#=
This test file verifies the functionality of the constructor transformation functions defined in src/constructors.jl. 
These tests ensure that @new macro calls are correctly transformed into tuple returns and that construct_TypeName functions are generated properly from constructor expressions.
=#

@testset "Constructor Transformations" begin
   # Test transform_new_calls
   @testset "transform_new_calls" begin
      # Test case 1: Simple @new call
      expr1 = :(
         function MyType(x, y)
            @new(x + 1, y * 2)
         end
      )
      transformed1 = transform_new_calls(expr1)  # Get the function body
      expected1 = :(
         function MyType(x, y)
            return (x + 1, y * 2,)
         end
      )
      @test MacroTools.striplines(transformed1) == MacroTools.striplines(expected1)

      # Test case 2: @new with no arguments
      expr2 = :(
         function EmptyType()
            @new()
         end
      )
      transformed2 = transform_new_calls(expr2)
      expected2 = :(
         function EmptyType()
            return ()
         end
      )
      @test MacroTools.striplines(transformed2) == MacroTools.striplines(expected2)
   end

   # Test generate_construct_function
   @testset "generate_construct_function" begin
      # Test case 1: Simple constructor with function body
      constructor_expr = transform_new_calls(:(
         function MyType(x::Int, y::Float64)
            x += 1
            y *= 2
            @new(x, y)
         end
      ))
      generated_func = generate_construct_function(constructor_expr)

      # Evaluate the generated function
      eval(generated_func)

      # Test the generated function
      result = construct_MyType(1, 2.0)
      @test result == (2, 4.0)

      # Test case 2: Constructor with no arguments
      constructor_expr2 = transform_new_calls(:(
         function EmptyType()
            @new()
         end
      ))
      generated_func2 = generate_construct_function(constructor_expr2)
      eval(generated_func2)
      result2 = construct_EmptyType()
      @test result2 == ()

      # Test case 3: Constructor with single argument and edge case
      constructor_expr2 = transform_new_calls(:(
         function OneArgType(x)
            res = @new(x+1)
            @warn "@new constructs a tuple: $res"
            res
         end
      ))
      generated_func3 = generate_construct_function(constructor_expr2)
      eval(generated_func3)
      result3 = construct_OneArgType(9)
      @test result3 == (10,)
   end
end

# Design Decisions:
# - The tests use MacroTools.striplines to compare expressions, ignoring line number differences that might occur during transformation.
# - The test cases cover both typical usage (with arguments) and edge cases (no arguments) to ensure robustness. 
# - Keyword arguments are not tested.