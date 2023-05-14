module PkgTest2
using Inherit, Test
using PkgTest1

@testset "definition errors" begin
	@test_throws "duplicate method definition" @abstractbase struct Fruit
		weight::Float32
		function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
		function cost_old(fruit::Fruit, unitprice::Float32)::Float32 end
	end
end

@abstractbase struct Fruit
	weight2::Float32
	function cost(fruit::Fruit, unitprice::Float32)::Float32 end
end

@implement struct Orange <: Fruit end
@implement struct Orange1 <: PkgTest1.Fruit end
function cost(item::Orange, unitprice::Number)
	item.weight2 * unitprice
end
function PkgTest1.cost(item::Orange1, unitprice::Number)
	item.weight * unitprice
end
@testset "implement @abstractbase from another module" begin
	@test fieldnames(Orange) == (:weight2,)
	@test fieldnames(Orange1) == (:weight,)

	Inherit.setreportlevel(@__MODULE__, ThrowError)
	@test_nothrows PkgTest2.__init__()
	@test_throws SettingsError Inherit.setreportlevel(@__MODULE__, DisableInitCheck)
end

end # module PkgTest2
