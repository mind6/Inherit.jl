module PkgTest2
using Inherit, Test
using PkgTest1


@abstractbase struct Fruit
	weight2::Float32
	function cost(fruit::Fruit, unitprice::Float32)::Float32 end
end
@abstractbase struct SummerFruit <: PkgTest1.Fruit
	season::String
	function isripe(fruit::SummerFruit)::Bool end
end

@implement struct Orange <: Fruit end
@implement struct Orange1 <: PkgTest1.Fruit end

"local function with local types"
function cost(item::Orange, unitprice::Number)
	item.weight2 * unitprice
end

"foreign module function using new local concrete type"
function PkgTest1.cost(item::Orange1, unitprice::Number)
	item.weight * unitprice
end

macro compiletime_modification()
	PkgTest1.clientmodule = __module__
	@info "installed clientmodule $(PkgTest1.clientmodule)"
end

@compiletime_modification

@verify_interfaces

function test()
	@testset "PkgTest2: implement @abstractbase from another module" begin
		# local super type
		@test fieldnames(Orange) == (:weight2,)

		# super type defined in foreign module
		@test fieldnames(Orange1) == (:weight,)

		# even though we modified PkgTest1 at compile time, at runtime we have a new instance
		@test PkgTest1.clientmodule === nothing

	end
end

end # module PkgTest2
