"""
Constructor inheritance

Introduce two special functions new(...) and super(...). These help to define and invoke the super class constructor, respectively. 

These may only be used inside the @abstractbase or @implement macros. If used outside, the special functions would have no information about the type it's operating on.
"""
macro abstractbase(x) end
macro implement(x) end
############## user code ##########

@abstractbase struct Food
	tax_exempt::Bool
	function Food()
		new(true)
	end
end

@abstractbase struct Fruit <: Food
	weight::Float64
	size::String
	function Fruit(w)
		# user_processing_A...
		new(super(), w * 0.9, "large")
	end
end

@implement struct Apple <: Fruit
	coresize::Int 
	function Apple()
		# user_processing_B...
		new(super(1.0), 3)
	end
	function Apple(w)
		# user_processing_C...
		Apple(super(w), 4)
	end
end

############# generated code ########
module A

abstract type Food end
function construct_Food()::Tuple
	(true, ) 
end

abstract type Fruit <: Food end
function construct_Fruit(w)::Tuple
	# user_processing_A...
	(construct_Food()..., w * 0.9, "large") 
end

struct Apple <: Fruit
	tax_exempt::Bool
	weight::Float64
	size::String
	coresize::Int 
	function Apple(args...) new(args...) end #this is required when there are external constructors using @super
	
	function Apple()
		# user_processing_B...
		new(construct_Fruit(1.0)..., 3)
	end
end
function Apple(w)
	# user_processing_C...
	Apple(construct_Fruit(w)..., 4)
end

println(Apple(1.33))
end  
######################################

"""
Multiple inheritance

The key part of the design is how to dispatch a Julia object to a type hierarchy it doesn't belong to. The easiest design would probably be to use a Union type to contain all the types with some trait. But it creates the problem that the union type needs to be overwritten each time a new user of the trait is loaded. This will cause massive invalidations, and at large scales, is in fact inpractical. 

The more practical design is wrap type instances inside container objects associated with the trait, and dispatch on the container object. This requires that in order to use a function that accepts a trait type (implemented as Julia abstract type), the function needs to be specificly imported against the user type, so that the user type can dispatch to a generated function that does the wrapping and redispatching. This should be an acceptable compromise that doesn't involve excessive number of function imports, because import specifications can be as generic as the function itself. 

The container object will override property accessors to redirect to the trait's user object. The performance and allocation impact should be analyzed. It may be possible to offer an alternative dispatch using static Type{T}, in addition to the user-friendly object based dispatch.

Functions that are actually required by a trait, will be automatically imported.

It should be possible to assign traits separately from definition of the user type, i.e. we can assign traits for types that have already been defined. But such traits may not have any member fields. The overall design should be a major improvement in terms of syntax similarity to standard Julia objects, and ease of reasoning about trait relationships, over Holy traits -- which have not been widely adopted.
"""
macro trait(x) end
macro import_traitfn(x) end
macro noop(x) end
############## user code ##########

@trait struct ImportedGoods
	tarrif
	function isexpensive(x::ImportedGoods) x.tarrif > 0 end
end

@trait struct SweetFood <: ImportedGoods
	sugarlevel

	#with an empty body, this declares an interface, and auto generates dispatch functions
	function describe(x::SweetFood) end	

	#with a body it defines a function, and also auto generates dispatch functions
	function advice(x::SweetFood) x.sugarlevel > 0.5 ? "ok" : "maybe" end
end

#note that this is not required by SweetFood trait, but it can be added later
@noop function howtoeatit(x::SweetFood) "cheerfully" end

@implement struct Apple <: Fruit _ <-- SweetFood
	coresize
end

#this requires no special dispatch and satisfies its declaration in the SweetFood trait
@noop function describe(x::Apple) "fruitful and tarty" end

#since howtoeatit was defined outside of trait definition, we need to explicitly import it for the type Apple, in order for dispatch to be created
@import_traitfn Apple, function howtoeatit(x::SweetFood) end

############# generated code ########
module B
import ..A

### trait definitions
abstract type ImportedGoods end
function isexpensive(x::ImportedGoods) x.tarrif > 0 end

abstract type SweetFood <: ImportedGoods end
function advice(x::SweetFood) x.sugarlevel > 0.5 ? "ok" : "maybe" end

#this is directly defined by the user (which we skipped with @noop so the file can run)
function howtoeatit(x::SweetFood) "cheerfully" end

### container objects
"""
these objects help dispatch and redirect properties to the 'x' object.
"""
struct SweetFoodContainer{T} <: SweetFood
	x::T
end
function Base.getproperty(value::SweetFoodContainer{T}, name::Symbol) where {T}
	Base.getfield(getfield(value, :x), name)
end
function Base.setproperty!(value::SweetFoodContainer{T}, name::Symbol, x) where {T}
	Base.setfield!(getfield(value, :x), name, x)
end

### trait user type
struct Apple <: A.Fruit
	tax_exempt::Bool
	weight::Float64
	size::String
	tarrif
	sugarlevel
	coresize::Int 
end

#these were generated because SweetFood trait requires 'isexpensive' and 'advice'.
function isexpensive(x::Apple) isexpensive(SweetFoodContainer(x)) end
function advice(x::Apple) advice(SweetFoodContainer(x)) end

#this was generated because we used @import_traitfn
function howtoeatit(x::Apple) howtoeatit(SweetFoodContainer(x)) end  

#this is directly defined by the user (which we skipped with @noop so the file can run)
function describe(x::Apple) "fruitful and tarty" end

############### test code ##############
a = Apple(true, 1.0, "medium", 0, 2, 4)
println("what's it like? $(describe(a))")
println("is it expensive? $(isexpensive(a))")
println("ok to eat? $(advice(a))")
println("how to eat this? $(howtoeatit(a))")

end
