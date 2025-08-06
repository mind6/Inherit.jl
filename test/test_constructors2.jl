# test/test_constructors.jl
using Test, MacroTools
using Inherit

import Inherit: transform_constructor

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
	# dump(MacroTools.striplines(expr))
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

 Design Decisions:
 - The tests use MacroTools.striplines to compare expressions, ignoring line number differences that might occur during transformation.
 - The test cases cover both typical usage (with arguments) and edge cases (no arguments) to ensure robustness. 
 - Keyword arguments are not tested.
 =#
 
@testset "Constructor Transformations" begin
	# Test transform_constructor
	@testset "transform_constructor with no super" begin
	   # Test case 1: Simple new call
	   expr1 = :(
		  function MyType(x, y)
			 new(x + 1, y * 2)
		  end
	   )
	   transformed1 = transform_constructor(:MyType, expr1; isabstract=true)  # Get the function body
	   expected1 = :(
		  function construct_MyType(x, y)
			 tuple(x + 1, y * 2,)
		  end
	   )
	   @test MacroTools.striplines(transformed1) == MacroTools.striplines(expected1)
 
	   # Test case 2: new with no arguments
	   expr2 = :(
		  function EmptyType()
			 new()
		  end
	   )
	   transformed2 = transform_constructor(:EmptyType, expr2; isabstract=true)  
	   expected2 = :(
		  function construct_EmptyType()
			 tuple()
		  end
	   )
	   @test MacroTools.striplines(transformed2) == MacroTools.striplines(expected2)
	end
 
	@testset "transform_constructor with super" begin
		# Test basic new transformation
		constructor_expr = :(
			function Food()
				new(true)
			end
		)
		
		transformed = transform_constructor(:Food, constructor_expr; isabstract=true)
		expected = :(
			function construct_Food()
				tuple(true,)
			end
		)
		
		@test MacroTools.striplines(transformed) == MacroTools.striplines(expected)
		
		# Test new with multiple arguments
		constructor_expr = :(
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		)
		
		transformed = transform_constructor(:Fruit, constructor_expr; isabstract=true, super_type_constructor=:construct_Food)
		expected = :(
			function construct_Fruit(w)
				tuple(construct_Food()..., w * 0.9, "large")
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
		
		transformed = transform_constructor(:NoNew, constructor_expr; isabstract=false)
		@test MacroTools.striplines(transformed) == MacroTools.striplines(constructor_expr)
	end

end	
module mc1
using Inherit, Test

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

@testset "integration test" begin
	a = Apple() 
	@test a.tax_exempt == true
end
end

##############################################################################

module mc2
using Inherit, Test

@abstractbase struct Food
	tax_exempt::Bool
	function cost(x::Food) end
end

@implement struct Fruit <: Food
	weight::Float64
	size::String
	function Fruit(w)
		new(false, w * 0.9, "large")
	end
end

function cost(x::Fruit) 
	x.weight * 2.0
end

@testset "inner constructor with no super" begin
	f = Fruit(1.0)
	@test f.tax_exempt == false
	@test cost(f) == 1.8
end

end
##############################################################################
module mc3
using Inherit, Test

@abstractbase struct Food
	tax_exempt::Bool
	function cost(x::Food) end
	function Food()
		new(true)
	end
end

@abstractbase struct Fruit <: Food
end

@implement struct Banana <: Fruit
	weight::Float64
	size::String
	function Banana(w)
		new(super(), w * 0.9, "large")
	end
end

function cost(x::Fruit) 
	x.weight * 2.0
end

@testset "skipped on level of super" begin
	f = Banana(1.0)
	@test f.tax_exempt == true
	@test cost(f) == 1.8
end

end