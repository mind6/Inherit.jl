module PkgTest3
using Inherit, Test
using PkgTest1

@abstractbase struct Fruit
	weight::Float32
	function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
	function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
end

end # module PkgTest3
