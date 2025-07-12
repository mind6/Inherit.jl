# test/test_constructors.jl
using Test, MacroTools
using Inherit

import Inherit: transform_new_calls, generate_construct_function

#=
This code demonstrates how different syntactic constructs in Julia create different 
Abstract Syntax Tree (AST) structures, even when they represent semantically identical code.

The test compares three ways of creating a function expression:
1. Using a macro that receives the function definition as an argument
2. Using the :() quote syntax to create an expression literal  
3. Using the quote...end block syntax

Key observations from the output:
- The macro (@my_macro) and :() syntax both produce identical AST structures with 
  head: Symbol function at the top level
- The quote...end syntax wraps the function in an additional block expression 
  (head: Symbol block), creating a nested structure where the actual function 
  definition is one level deeper in the AST

This difference is important for macro development because macros need to handle 
expressions correctly regardless of how they were constructed. The quote...end 
syntax adds an extra layer that may need to be unwrapped when processing 
function definitions in macros.

The striplines() call removes line number nodes to make the comparison clearer 
by focusing on the structural differences rather than metadata.
=#
function show_expr(expr)
	dump(MacroTools.striplines(expr))
end

macro my_macro(expr)
	show_expr(expr)
end
@testset "macro vs quote" begin
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
end
 
 
 #=
 This test file verifies the functionality of the constructor transformation functions defined in src/constructors.jl. 
 These tests ensure that new(...) special function calls are correctly transformed into tuple returns and that construct_TypeName functions are generated properly from constructor expressions.
 =#
 
 @testset "Constructor Transformations" begin
	# Test transform_new_calls
	@testset "transform_new_calls" begin
	   # Test case 1: Simple new call
	   expr1 = :(
		  function MyType(x, y)
			 new(x + 1, y * 2)
		  end
	   )
	   transformed1 = transform_new_calls(expr1)  # Get the function body
	   expected1 = :(
		  function MyType(x, y)
			 return (x + 1, y * 2,)
		  end
	   )
	   @test MacroTools.striplines(transformed1) == MacroTools.striplines(expected1)
 
	   # Test case 2: new with no arguments
	   expr2 = :(
		  function EmptyType()
			 new()
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
			 new(x, y)
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
			 new()
		  end
	   ))
	   generated_func2 = generate_construct_function(constructor_expr2)
	   eval(generated_func2)
	   result2 = construct_EmptyType()
	   @test result2 == ()
 
	   # Test case 3: Constructor with single argument and edge case
	   constructor_expr2 = transform_new_calls(:(
		  function OneArgType(x)
			 res = new(x+1)
			 @warn "new constructs a tuple: $res"
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

@testset "Constructor transformation functions" begin
	# Test transform_new_calls
	@testset "transform_new_calls" begin
		# Test basic new transformation
		constructor_expr = :(
			function Food()
				new(true)
			end
		)
		
		transformed = transform_new_calls(constructor_expr)
		expected = :(
			function Food()
				return (true,)
			end
		)
		
		@test MacroTools.striplines(transformed) == MacroTools.striplines(expected)
		
		# Test new with multiple arguments
		constructor_expr = :(
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		)
		
		transformed = transform_new_calls(constructor_expr)
		expected = :(
			function Fruit(w)
				return (super(), w * 0.9, "large")
			end
		)
		@test MacroTools.striplines(transformed) == MacroTools.striplines(expected)
		

		
		# Test constructor with no new doesn't change
		constructor_expr = :(
			function NoNew()
				x = 1
				return x
			end
		)
		
		transformed = transform_new_calls(constructor_expr)
		@test MacroTools.striplines(transformed) == MacroTools.striplines(constructor_expr)
	end
	
	# Test generate_construct_function
	@testset "generate_construct_function" begin
		# Test basic constructor transformation
		constructor_expr = :(
			function Food()
				return (true,)
			end
		)
		
		result = generate_construct_function(constructor_expr)
		expected = :(
			function construct_Food()::Tuple
				return (true,)
			end
		)
		
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
		
		# Test constructor with arguments
		constructor_expr = :(
			function Fruit(w)
				return (construct_Food()..., w * 0.9, "large")
			end
		)
		
		result = generate_construct_function(constructor_expr)
		expected = :(
			function construct_Fruit(w)::Tuple
				return (construct_Food()..., w * 0.9, "large")
			end
		)
		
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
		
		# Test constructor with complex body
		constructor_expr = :(
			function Complex(a, b; kw=1)
				x = a + b
				y = x * kw
				return (x, y)
			end
		)
		
		result = generate_construct_function(constructor_expr)
		expected = :(
			function construct_Complex(a, b; kw=1)::Tuple
				x = a + b
				y = x * kw
				return (x, y)
			end
		)
		
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
	end
	
	# Integration test with actual execution
	@testset "Integration test with execution" begin
		# Create a module to contain our test types and functions
		test_module = Module()
		
		# Define Food constructor
		food_constructor = :(
			function Food()
				new(true)
			end
		)
		
		# Process Food constructor
		food_transformed = transform_new_calls(food_constructor)
		food_construct = generate_construct_function(food_transformed)
		
		# Evaluate in test module
		Core.eval(test_module, food_construct)
		
		# Define Fruit constructor that uses Food constructor
		fruit_constructor = :(
			function Fruit(w)
				new(construct_Food()..., w * 0.9, "large")
			end
		)
		
		# Process Fruit constructor
		fruit_transformed = transform_new_calls(fruit_constructor)
		fruit_construct = generate_construct_function(fruit_transformed)
		
		# Evaluate in test module
		Core.eval(test_module, fruit_construct)
		
		# Now test actual invocation
		result = test_module.construct_Food()
		@test result == (true,)
		
		result = test_module.construct_Fruit(1.0)
		@test result == (true, 0.9, "large")
		
		# Test with another weight value
		result = test_module.construct_Fruit(2.0)
		@test result == (true, 1.8, "large")
	end
end

module mc1
	using Inherit
	
	@abstractbase struct Food
		tax_exempt::Bool
		function Food()
			new(true)
		end
	end

	@abstractbase struct Fruit <: Food
		weight::Float64
		size::String
		function Fruit(w)
			# user_processing_A...
			new(super(), w * 0.9, "large")
		end
	end

	@implement struct Apple <: Fruit
		coresize::Int 
		function Apple()
			# user_processing_B...
			new(super(1.0), 3)
		end
		function Apple(w)
			# user_processing_C...
			Apple(super(w), 4)
		end
	end

	a = Apple() 
	@test a.tax_exempt == true
end