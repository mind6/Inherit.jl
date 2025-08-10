# Introduction 

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

```@meta
DocTestSetup = quote
	import Inherit
	ENV["JULIA_DEBUG"] = ""
end
```

# Quick Start

Use `@abstractbase` to declare an abstract supertype, and use `@implement` to inherit from such a type. Standard `struct` syntax is used.

```jldoctest
using Inherit

"
Base type of Fruity objects. 
Creates a julia native type with 
	`abstract type Fruit end`
"
@abstractbase struct Fruit
	weight::Float64
	"declares an interface which must be implemented"
	function cost(fruit::Fruit, unitprice::Float64) end
end

"
Concrete type which represents an apple, inheriting from Fruit.
Creates a julia native type with 
	`struct Apple <: Fruit weight::Float64; coresize::Int end`
"
@implement struct Apple <: Fruit 
	coresize::Int
end

"
Implements supertype's interface declaration `cost` for the type `Apple`
"
function cost(apple::Apple, unitprice::Float64)
	apple.weight * unitprice * (apple.coresize < 5 ? 2.0 : 1.0)
end

println(cost(Apple(3.0, 4), 1.0))

# output
6.0
```
Note that the definition of `cost` function inside of `Fruit` is interpreted as an interface declaration; it does not result in a method being defined.

# Limitations

Parametric types are supported; all type parameters must match exactly when inheriting.

Methods are examined only for their positional arguments. Inherit.jl has no special knowledge of keyword arguments, but this may improve in the future.


Short form function definitions such as `f() = nothing` are not supported for method declaration; use the long form `function f() end` instead. Using short form for method implementation can be problematic as well (e.g. when the function is imported from another module); it's generally safer to use long form.

## Multiple inheritance

Multiple inheritance is currently not supported, but is being planned. It will have the following syntax:

```julia
@abstractbase struct Fruit
	weight::Float64
	function cost(fruit::Fruit, unitprice::Float64) end
end

@trait struct SweetFood
	sugartype::Symbol
	"
	Subtype must define:
		function sugarlevel(obj::T) end  
	where T<--SweetFood
	"
	function sugarlevel(obj<--SweetFood) end  
end

@implement struct Apple <: Fruit _ <-- SweetFood 
	coresize::Int
end

function sugarlevel(apple::Apple) "depends on "*join(fieldnames(Apple),", ") end	

sugarlevel(Apple(3.3, "sucrose", 4))
```
```
"depends on weight, sugartype, coresize"
```

```@index
```

```@docs
@abstractbase
@implement
```
