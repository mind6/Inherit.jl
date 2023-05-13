module MN
	using Inherit, Test

	@abstractbase struct Fruit
		size::Float32
		function cost(fruit::Fruit, unitprice::Float32)::Float32 end
	end

"""
```
@interface struct SweetFood
	sugartype::Symbol
	"
	User must define:
		function sugarlevel(obj::T) end  
	where T<--SweetFood
	"
	function sugarlevel(obj<--SweetFood) end  
end
```
generates:
"""
	struct SweetFood{T}
		ptr::T
		function SweetFood(ptr::T) where T
			@assert T <-- SweetFood "$T does not implement `@interface SweetFood`"
			new{T}(ptr)
		end
	end
"^^^ end generation ^^^"

"""
```
@implement struct Apple <: Fruit <-- SweetFood 
	weight::Float32
end
```
generates:
"""
	struct Apple <: Fruit
		size::Float32
		sugartype::Symbol
		weight::Float32
	end
	function sugarlevel(obj::SweetFood{<:Apple})  sugarlevel(obj.ptr) end
	Inherit.:(<--)(::Type{Apple},::Type{SweetFood}) = true
	Base.in(::Apple, ::Type{SweetFood}) = true
"^^^ end generation ^^^"
	
	"User must define this. If we required defining sugarlevel(apple::SweetFood{Apple}) instead, it may improves clarity, but it has a performance cost when container objects have to created just to invoke the function."
	function sugarlevel(apple::Apple) "depends on "*join(fieldnames(Apple),", ") end	

"""
```
@implement struct Cookie <-- SweetFood 
end
```
generates:
"""
	struct Cookie <: Any
		sugartype::Symbol
	end
	function sugarlevel(obj::SweetFood{<:Cookie})  sugarlevel(obj.ptr) end		
	Inherit.:(<--)(::Type{Cookie},::Type{SweetFood}) = true
	Base.in(::Cookie, ::Type{SweetFood}) = true
"^^^ end generation ^^^"

	"user must define this"
	function sugarlevel(cookie::Cookie) "always high" end	

	@testset "interface tests" begin
		@test Apple <-- SweetFood
		@test Apple(1, :white, 1) in SweetFood
		vec =[SweetFood(Apple(1.2, :white, 1.3)), SweetFood(Cookie(:brown))]
		@show [sugarlevel(obj) for obj in vec]
	end
end

