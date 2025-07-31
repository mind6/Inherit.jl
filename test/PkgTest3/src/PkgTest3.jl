module PkgTest3
using Inherit, Test
using PkgTest2
import PkgTest2.PkgTest1: cost

# @abstractbase struct Strawberry end

@implement struct Strawberry <: PkgTest2.SummerFruit
	color::String
end
function PkgTest2.isripe(fruit::Strawberry)::Bool true end

function cost(item::Strawberry, unitprice::Number)
	"$(item.color) strawberry costs $(item.weight * unitprice)"
end
@verify_interfaces

function test()
	@testset "PkgTest3: hopping across 2 packages" begin
		@test cost(Strawberry(1.5, "early", "red"), 2.0) == "red strawberry costs 3.0"
	end
end

end # module PkgTest3
