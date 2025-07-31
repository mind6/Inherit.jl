module M20
	using Inherit, Test

	@abstractbase struct Fruit{T}
		size::T
	end
	@implement struct Apple <: Fruit
	end
	@implement struct Orange{U} <: Fruit
		weight::U
	end

	@abstractbase struct NiceFruit{K} <: Fruit
		price::K
	end

	@implement struct Strawberry{L} <: NiceFruit
		location::L
	end
	@verify_interfaces

	@testset "inheriting parametric fields" begin
		a = Apple(Int(1))
		b = Orange(Int(2), Float32(3))
		c = Strawberry("large", Float64(3.2), "far away")
		@show c
		@test collect(typeof(a).parameters) == [Int]
		@test collect(typeof(b).parameters) == [Int, Float32]
		@test collect(typeof(c).parameters) == [String, Float64, String]
	end
end
