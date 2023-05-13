module PkgTest1
using Inherit, Test 

greet() = print("Hello World!")

"base types can be documented"
@abstractbase struct NoSubTypesOK impliedAnyOK end

"second base type"
@abstractbase struct Fruit
	weight::Float32
	function cost_old(fruit::PkgTest1.Fruit, unitprice::Float32)::Float32 end
end

### should show a warning message, indicating we're going to reset data for the type
"third base type"
@abstractbase struct Fruit
	weight::Float32
	"a useful function"
	function cost(fruit::PkgTest1.Fruit, unitprice::Float32)::Float32 end
end

"derived types can also be documented"
@implement struct Orange <: PkgTest1.Fruit end
@implement struct Kiwi <: Fruit end
@implement struct Apple <: Fruit 
	coresize::Int 
end
"has more than"
function cost(fruit::Union{Orange, Kiwi}, unitprice::Number)
	unitprice * fruit.weight
end
"one part"
function cost(apple::Apple, unitprice::Float32)
	unitprice * (apple.weight + apple.coresize) 
end

function run()
	@info "Running PkgTest1 post init tests..."
	@testset "basic field inheritance" begin 
		@test_throws ArgumentError fieldnames(Fruit)		#interfaces are abstract types
		@test fieldnames(Orange) == fieldnames(Kiwi) == (:weight,)
		@test fieldnames(Apple) == (:weight, :coresize)
	end

	@testset "method dispatch from abstractbase" begin
		basket = Fruit[Orange(1), Kiwi(2.0), Apple(3,4)]
		@test [cost(item, 2.0f0) for item in basket] == [2.0f0, 4.0f0, 14.0f0]
	end

	@testset "method comments require __init__" begin
		@test strip(string(@doc(NoSubTypesOK))) == "base types can be documented"
		@test strip(string(@doc(Fruit))) == "third base type"
		@test strip(string(@doc(Orange))) == "derived types can also be documented"

		@test_nothrows __init__()
		#NOTE: unfortunately, the method declaration comment will be last one in the module
		@test replace(string(@doc PkgTest1.cost), "\n"=>"") == "has more thanone parta useful function"
	end
end

end # module PkgTest1
