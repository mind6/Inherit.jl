module PkgTest3
using Inherit, Test
using PkgTest2
import PkgTest2.PkgTest1: cost

# @abstractbase struct Strawberry end

@implement struct Strawberry <: PkgTest2.SummerFruit
	color::String
	function Strawberry(color)
		new(super(), color)
	end

	# since we defined inner constructor above, we need to bring back the default constructor
	function Strawberry(args...)
		new(args...)
	end
end
function PkgTest2.isripe(fruit::Strawberry)::Bool true end

function cost(item::Strawberry, unitprice::Number)
	"$(item.color) strawberry costs $(item.weight * unitprice)"
end
@verify_interfaces

function test()
	@testset "PkgTest3: hopping across 2 packages" begin
		@test cost(Strawberry(1.5, "early", "red"), 2.0) == "red strawberry costs 3.0"

		# constructor inheritance across 2 packages
		@test Strawberry("pink") == Strawberry(1.2, "summer", "pink")
	end
end

end # module PkgTest3
