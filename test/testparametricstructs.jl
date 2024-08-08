# module M20
# 	using Inherit, Test

# 	@abstractbase struct Fruit{T}
# 		size::T
# 	end
# 	@implement struct Apple <: Fruit
# 	end
# end

ex = quote
	struct Fruit{T <: Real, T2}
		size::T
	end
end
ex2 = quote
	struct Fruit
		size::T
	end
end
# @capture(ex,  struct T_Symbol{P__} lines__ end)