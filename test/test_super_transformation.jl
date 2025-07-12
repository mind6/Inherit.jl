# test/test_super_transformation.jl
using Test, MacroTools
using Inherit

import Inherit: transform_super_calls, get_supertype_constructor_name

@testset "Super() transformation exploration" begin
    # First, let's create a test module to explore the data structures
    test_module = Module()
	 Core.eval(test_module,:(using Inherit))
	 
    # Set up the module database
    Inherit.setup_module_db(test_module)
    
    @testset "Explore existing data structures" begin
        # Create a simple hierarchy in our test module
        Core.eval(test_module, quote
            using Inherit
            
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
        
        # For now, let's create a simple version that just identifies super() calls
        function find_super_calls(expr)
            super_calls = []
            MacroTools.postwalk(expr) do x
                if @capture(x, super(args__))
                    push!(super_calls, (args,))
                elseif @capture(x, super())
                    push!(super_calls, ())
                end
                x
            end
            return super_calls
        end
        
        super_calls = find_super_calls(constructor_expr)
        @test length(super_calls) == 1
        @test super_calls[1] == ()  # super() with no arguments
        
        # Test with arguments
        constructor_expr2 = :(
            function Apple()
                new(super(1.0), 3)
            end
        )
        
        super_calls2 = find_super_calls(constructor_expr2)
        @test length(super_calls2) == 1
        @test super_calls2[1] == (1.0,)
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

@testset "Cross-module super() calls" begin
    # Create two modules to test cross-module inheritance
    base_module = Module()
    derived_module = Module()
    
    # Set up both modules
    Inherit.setup_module_db(base_module)
    Inherit.setup_module_db(derived_module)
    
    # Define base type in base_module
    Core.eval(base_module, quote
        using Inherit
        
        @abstractbase struct Food
            tax_exempt::Bool
            function Food()
                new(true)
            end
        end
    end)
    
    # Define derived type in derived_module that inherits from base_module.Food
    Core.eval(derived_module, quote
        using Inherit
        
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
    
    # The super() call should resolve to base_module.construct_Food
    # This test helps us understand cross-module constructor resolution
end