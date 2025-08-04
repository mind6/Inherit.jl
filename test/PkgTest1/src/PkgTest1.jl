module PkgTest1

using Inherit

export Fruit, Orange, Kiwi, Apple, cost, NoSubTypesOK

# used by PkgTest2 to test compile time modification of this module
global clientmodule = nothing

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
	function Fruit()
		new(1.2)
	end
end

"derived types can also be documented"
@implement struct Orange <: PkgTest1.Fruit end
@implement struct Kiwi <: Fruit end
@implement struct Apple <: Fruit 
	coresize::Int 
	function Apple(coresize)
		new(super(), coresize)
	end
end
"has more than"
function cost(fruit::Union{Orange, Kiwi}, unitprice::Number)
	unitprice * fruit.weight
end
"one part"
function cost(apple::Apple, unitprice::Float32)
	unitprice * (apple.weight + apple.coresize) 
end

@verify_interfaces


end # module PkgTest1
