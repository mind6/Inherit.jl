# test/test_constructors.jl
using Test, MacroTools
include("../src/constructors.jl")

@testset "Constructor transformation functions" begin
    # Test transform_new_calls
    @testset "transform_new_calls" begin
        # Test basic @new transformation
        constructor_expr = :(
            function Food()
                @new(true)
            end
        )
        
        transformed = transform_new_calls(constructor_expr)
        expected = :(
            function Food()
                return (true,)
            end
        )
        
        @test MacroTools.striplines(transformed) == MacroTools.striplines(expected)
        
        # Test @new with multiple arguments
        constructor_expr = :(
            function Fruit(w)
                @new(@super(), w * 0.9, "large")
            end
        )
        
        transformed = transform_new_calls(constructor_expr)
        expected = :(
            function Fruit(w)
                return (@super(), w * 0.9, "large")
            end
        )
        @test MacroTools.striplines(transformed) == MacroTools.striplines(expected)
        

        
        # Test constructor with no @new doesn't change
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
                @new(true)
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
                @new(construct_Food()..., w * 0.9, "large")
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