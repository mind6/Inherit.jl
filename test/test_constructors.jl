# test/test_super_transformation.jl
using Test, MacroTools
using Inherit

import Inherit: transform_constructor

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
		modinfo = Base.invokelatest(getproperty, test_module, Inherit.H_COMPILETIMEINFO)
		
		@test haskey(modinfo.localtypespec, :Food)
		@test haskey(modinfo.localtypespec, :Fruit)
		
		# Check if constructor definitions were stored
		@test haskey(modinfo.consdefs, :Food)
		@test haskey(modinfo.consdefs, :Fruit)
		
		# Examine the constructor definitions
		food_constructors = modinfo.consdefs[:Food]
		fruit_constructors = modinfo.consdefs[:Fruit]
		
		@test length(food_constructors) == 1
		@test length(fruit_constructors) == 1
		
		# Check that we can access the supertype information
		fruit_spec = modinfo.localtypespec[:Fruit]
		@test length(fruit_spec.fields) > 1  # Should have inherited fields from Food
	end
end

@testset verbose=true "transform_constructor" begin


	@testset "transform new() only" begin
		expr = :(
			function Apple()
				new(1.0, 3)
			end
		)
		result = transform_constructor(:Apple, expr; isabstract=true, super_type_constructor=nothing)
		expected = :(
			function construct_Apple()
				tuple(1.0, 3)
			end
		)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
	end

	@testset "transform super() only" begin
		expr = :(
			function Apple()
				new(super(1.0), 3)
			end
		)
		result = transform_constructor(:Apple, expr; isabstract=false, super_type_constructor=:construct_Fruit)
		expected = :(function Apple()
				new(construct_Fruit(1.0)..., 3)
		end)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
	end

	@testset "super() will expand in functions other than new()" begin
		expr = :(
			function Apple()
				Apple(super(1.0), 3)
			end
		)
		result = transform_constructor(:Apple, expr; isabstract=false, super_type_constructor=:construct_Fruit)
		expected = :(function Apple()
			Apple(construct_Fruit(1.0)..., 3)
		end)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
	end

	@testset "transform both new() and super()" begin
		# Test transforming super() calls in constructor bodies
		expr = :(
			function Fruit(w)
				new(super(), w * 0.9, "large")
			end
		)
		result = transform_constructor(:Fruit, expr; isabstract=true, super_type_constructor=:construct_Food)
		expected = :(
			function construct_Fruit(w)
				tuple(construct_Food()..., w * 0.9, "large")
			end
		)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)
		
		# Test with arguments
		expr2 = :(
			function Apple()
				do_something()
				return new(super(1.0), 3)
				do_something_else()
			end
		)
		result2 = transform_constructor(:Apple, expr2; isabstract=true, super_type_constructor=:construct_Fruit)
		expected2 = :(function construct_Apple()
			do_something()
			return tuple(construct_Fruit(1.0)..., 3)
			do_something_else()
		end)
		@test MacroTools.striplines(result2) == MacroTools.striplines(expected2)
	end

	@testset "new() or no new() in abstract constructor" begin
		expr = :(
			function Apple()
				Apple(super(1.0), 3)
			end
		)
		result = transform_constructor(:Apple, expr; isabstract=false, super_type_constructor=:construct_Fruit)
		expected = :(function Apple()
			Apple(construct_Fruit(1.0)..., 3)
		end)
		@test MacroTools.striplines(result) == MacroTools.striplines(expected)

		expr = :(
			function Apple()
				Apple(super(1.0), 3)
			end
		)
		@test_throws "new() calls are required in abstract constructors" transform_constructor(:Apple, expr; isabstract=true, super_type_constructor=:construct_Fruit)
	end
end

@testset "Super() calls must be the first argument" begin
	expr1 = :(
		function Fruit(w)
			super("is confused")
		end
	)
	@test_throws "super() calls can only appear as the first argument of a function (such as new() or SomeType())" transform_constructor(:Fruit, expr1; isabstract=false, super_type_constructor=:construct_Food)

	expr2 = :(
		function Fruit(w)
			new(:abc, super("is confused"))
		end
	)
	@test_throws "super() calls can only appear as the first argument of a function (such as new() or SomeType())"  transform_constructor(:Fruit, expr2; isabstract=true, super_type_constructor=:construct_Food)
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

	modinfoA = Base.invokelatest(getproperty, A, Inherit.H_COMPILETIMEINFO)
	modinfoB = Base.invokelatest(getproperty, B, Inherit.H_COMPILETIMEINFO)

	cons_S = modinfoA.consdefs[:Food][1]
	cons_T = modinfoB.consdefs[:Fruit][1]

	# @show cons_T.transformed_expr

	@testset "cross_module_calls" begin
		imported_consname = Inherit.locate_supertype_constructor(B, :Fruit)
		@test isdefined(B, imported_consname)
		@test Base.invokelatest(getproperty, B, imported_consname)() == (true,)

		@test isdefined(A,:construct_Food)
		@test A.construct_Food() == (true,)
	end

	module C
		using Inherit
		import ..B: Fruit

		@implement struct Banana <: Fruit
			source::String
			function Banana(s)
				new(super(9.9), s)
			end
		end
	end

	@testset "calling concrete constructor" begin
		banana = C.Banana("from the tropics")
		@test banana.tax_exempt == true
		@test banana.weight == 0.9 * 9.9
		@test banana.size == "large"
		@test banana.source == "from the tropics"
	end
end
# dump(MacroTools.striplines(:(
# 	struct Banana <: Fruit
# 		a::int
# 		function Banana(s)
# 			new(super(9.9), s)
# 		end
# 	end
# )))

@testset "Cross-module super() calls" begin
	# Create two modules to test cross-module inheritance
	base_module = Module(:base_mod)
	derived_module = Module(:derived_mod)
	
	# Set up both modules
	Core.eval(base_module, :(using Inherit))
	Core.eval(derived_module, :(using Inherit))
	Inherit.setup_module_db(base_module)
	Inherit.setup_module_db(derived_module)

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
	modinfo = Base.invokelatest(getproperty, derived_module, Inherit.H_COMPILETIMEINFO)
	@test haskey(modinfo.localtypespec, :Fruit)
	
	fruit_spec = modinfo.localtypespec[:Fruit]
	@test length(fruit_spec.fields) > 1  # Should have inherited tax_exempt field
	
	base_modinfo = Base.invokelatest(getproperty, base_module, Inherit.H_COMPILETIMEINFO)
	derived_modinfo = Base.invokelatest(getproperty, derived_module, Inherit.H_COMPILETIMEINFO)

	cons_S = base_modinfo.consdefs[:Food][1]
	cons_T = derived_modinfo.consdefs[:Fruit][1]

	@test Core.eval(base_module, cons_S.transformed_expr)() == (true,)
	@test isdefined(base_module,:construct_Food)
	@test base_module.construct_Food() == (true,)
	# The super() call should resolve to base_module.construct_Food
	# @show cons_T.transformed_expr

	@test isdefined(derived_module,:construct_Fruit)

	# This test helps us understand cross-module constructor resolution
end