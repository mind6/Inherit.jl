# test/test_super_transformation.jl
using Test, MacroTools
using Inherit

import Inherit: transform_new_calls, get_supertype_constructor_name

@testset "Super() transformation exploration" begin
	# First, let's create a test module to explore the data structures
	test_module = Module()
	 Core.eval(test_module,:(using Inherit))

	# Set up the module database
	Inherit.setup_module_db(test_module)
	
	@testset "Explore existing data structures" begin
		# Create a simple hierarchy in our test module
		Core.eval(test_module, quote
			
			Inherit.@abstractbase struct Food
				tax_exempt::Bool
				function Food()
					new(true)
				end
			end
			
			Inherit.@abstractbase struct Fruit <: Food
				weight::Float64
				size::String
				function Fruit(w)
					new(super(), w * 0.9, "large")
				end
			end
		end)
		
		# Now let's explore what data structures were created
		DBSPEC = getproperty(test_module, Inherit.H_TYPESPEC)
		DBCON = getproperty(test_module, Inherit.H_CONSTRUCTOR_DEFINITIONS)
		
		@test haskey(DBSPEC, :Food)
		@test haskey(DBSPEC, :Fruit)
		
		# Check if constructor definitions were stored
		food_ident = Inherit.TypeIdentifier((fullname(test_module), :Food))
		fruit_ident = Inherit.TypeIdentifier((fullname(test_module), :Fruit))
		
		@test haskey(DBCON, food_ident)
		@test haskey(DBCON, fruit_ident)
		
		# Examine the constructor definitions
		food_constructors = DBCON[food_ident]
		fruit_constructors = DBCON[fruit_ident]
		
		@test length(food_constructors) == 1
		@test length(fruit_constructors) == 1
		
		# Check that we can access the supertype information
		fruit_spec = DBSPEC[:Fruit]
		@test length(fruit_spec.fields) > 1  # Should have inherited fields from Food
	end
end

@testset "Super() call transformation" begin
	@testset "Basic super() transformation" begin
		# Test transforming super() calls in constructor bodies
		constructor_expr = :(
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		)
		result = transform_new_calls(constructor_expr, :Food)
		expected = :(
			function Fruit(w)
				return (construct_Food()..., w * 0.9, "large")
			end
		)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
		
		# Test with arguments
		constructor_expr2 = :(
			function Apple()
				new(super(1.0), 3)
			end
		)
		result2 = transform_new_calls(constructor_expr2, :Fruit)
		expected2 = :(function Apple()
			return (construct_Fruit(1.0)..., 3)
		end)
		@test MacroTools.striplines(result2) == MacroTools.striplines(expected2)
	end
	
	@testset "Get supertype constructor name" begin
		# Create a function to determine the supertype constructor name
		# This should use the existing inheritance data structures
		function get_supertype_constructor_name(current_module, current_type_name)
			DBSPEC = getproperty(current_module, Inherit.H_TYPESPEC)
			
			# For now, let's implement a simple version that looks at the type hierarchy
			# We need to find what this type inherits from
			
			# This is a placeholder - we need to implement the actual logic
			# based on how @abstractbase stores supertype information
			return :construct_Food  # placeholder
		end
		
		# Test this with our test module from above
		# This test will help us understand what we need to implement
		@test_skip get_supertype_constructor_name(test_module, :Fruit) == :construct_Food
	end
end

module cross_module_calls
	module A
		using Inherit
		@abstractbase struct Food
			tax_exempt::Bool
			function Food()
				 new(true)
			end
	  end
	end

	module B
		using Inherit
		import ..A
		@abstractbase struct Fruit <: A.Food
			weight::Float64
			size::String
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		end
	end

	using Inherit, Test, .A, .B

	A_CONSDEF = getproperty(A, Inherit.H_CONSTRUCTOR_DEFINITIONS)
	B_CONSDEF = getproperty(B, Inherit.H_CONSTRUCTOR_DEFINITIONS)
	identS = Inherit.TypeIdentifier((fullname(A), :Food))
	identT = Inherit.TypeIdentifier((fullname(B), :Fruit))
	cons_S = A_CONSDEF[identS][1]
	cons_T = B_CONSDEF[identT][1]

	@show cons_T.transformed_expr

	@testset "cross_module_calls" begin
		@test !isdefined(A,:construct_Food)
		@test Core.eval(A, cons_S.transformed_expr)() == (true,)
		@test isdefined(A,:construct_Food)
	end
end
@testset "Cross-module super() calls" begin
	# Create two modules to test cross-module inheritance
	base_module = Module(:base_mod)
	derived_module = Module(:derived_mod)
	
	# Set up both modules
	Inherit.setup_module_db(base_module)
	Inherit.setup_module_db(derived_module)
	Core.eval(base_module, :(using Inherit))
	Core.eval(derived_module, :(using Inherit))

	# Define base type in base_module
	Core.eval(base_module, quote
		@abstractbase struct Food
			tax_exempt::Bool
			function Food()
				new(true)
			end
		end
	end)
	
	# Define derived type in derived_module that inherits from base_module.Food
	Core.eval(derived_module, quote
		@abstractbase struct Fruit <: $(base_module).Food
			weight::Float64
			size::String
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		end
	end)
	
	# Test that the inheritance worked across modules
	derived_DBSPEC = getproperty(derived_module, Inherit.H_TYPESPEC)
	@test haskey(derived_DBSPEC, :Fruit)
	
	fruit_spec = derived_DBSPEC[:Fruit]
	@test length(fruit_spec.fields) > 1  # Should have inherited tax_exempt field
	
	base_CONSDEF = getproperty(base_module, Inherit.H_CONSTRUCTOR_DEFINITIONS)
	derived_CONSDEF = getproperty(derived_module, Inherit.H_CONSTRUCTOR_DEFINITIONS)

	identS = Inherit.TypeIdentifier((fullname(base_module), :Food))
	identT = Inherit.TypeIdentifier((fullname(derived_module), :Fruit))
	cons_S = base_CONSDEF[identS][1]
	cons_T = derived_CONSDEF[identT][1]

	@test !isdefined(base_module,:construct_Food)
	@test Core.eval(base_module, cons_S.transformed_expr)() == (true,)
	@test isdefined(base_module,:construct_Food)

	# The super() call should resolve to base_module.construct_Food
	@show cons_T.transformed_expr

	@test_skip isdefined(derived_module,:construct_Fruit)

	# This test helps us understand cross-module constructor resolution
end