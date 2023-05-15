# Introduction 

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

```@meta
DocTestSetup = quote
	import Inherit
	ENV["JULIA_DEBUG"] = ""
	ENV[Inherit.E_SUMMARY_LEVEL] = "info"
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

!!! info 
	What this declaration means is that when invoking the `cost` function, passing an object which is a subtype of `Fruit` (declared with the `@implement` macro) to the `fruit::Fruit` parameter must be able to dispatch to some method instance. This is verified when a module is first loaded. 

# Interaction with modules

Object oriented programming is most helpful when applications have grown across multiple modules. Even though __Inherit.jl__ can be used inside scripts, its true use case is to assert __common interfaces__ shared by different data types. __Verification__ of method declarations takes place in the `__init__()` function of the module which the implementing type belongs to (i.e. where the `@implement` macro is used).

## The module `__init__()` function

The specially named function `__init__()` is called after the module has been fully loaded by Julia. If an interface definition has not been met, an exception will be thrown.

```jldoctest
module M1
	using Inherit
	@abstractbase struct Fruit
		weight::Float64
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	@implement struct Apple <: Fruit end
	@implement struct Orange <: Fruit end
	@implement struct Kiwi <: Fruit end
	function cost(fruit::Union{Apple, Kiwi}, unitprice::Float64) 1.0 end
end

# output
ERROR: InitError: ImplementError: subtype M1.Orange missing Tuple{typeof(M1.cost), M1.Orange, Float64} declared as:
function cost(fruit::Fruit, unitprice::Float64)
[...]
```
Upon loading module `M1`, Inherit.jl throws an `ImplementError` from the `__init__()` function, telling you that it's looking for a method signature that can dispatch `cost(::M1.Orange, ::Float64)`. It makes no complaints about `Apple` and `Kiwi` because their dispatch can be satisfied

## The `@postinit` macro

The presence of an `@abstractbase` or `@implement` causes Inherit.jl to generate and __overwrite__ the module's `__init__()` function. To execute your own module initiation code, the `@postinit` macro is available. It accepts a function as argument and registers that function to be executed after `__init__()`. Multiple occurrences of `@postinit` will result in each function being called successively.

# Putting it all together

Let's demonstrate `@postinit` as well as other features in a more extended example.

```jldoctest
module M1
	using Inherit

	@abstractbase struct Fruit
		weight::Float64
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	function cost(item::Fruit, unitprice::Number)
		unitprice * item.weight
	end		
end

module M2
	using Inherit
	import ..M1

	@abstractbase struct Berry <: M1.Fruit
		function pack(time::Int, bunch::Dict{String, AbstractVector{<:Berry}})::Float32 end
	end

	@implement struct BlueBerry <: Berry end
	function pack(time::Number, bunch::Dict{String, AbstractVector{<:BlueBerry}})::Float32 end

end
nothing

# output
[ Info: Inherit.jl: processed M1 with 1 supertype having 1 method requirement. 0 subtypes were checked with 0 missing methods.
[ Info: Inherit.jl: processed M2 with 1 supertype having 2 method requirements. 1 subtype was checked with 0 missing methods.
```

## Changing the reporting level
 
By default, module `__init__()` writes a summary message at the `Info` log level. You can change this by setting `ENV["INHERIT_JL_SUMMARY_LEVEL"]` to one of `["debug", "info", "warn", "error", "none"]`.

# Limitations
## Multiple inheritance

# API
| environment variable | value | description|
|---|---|---|
|JULIA\_DEBUG | "Inherit" | Enables printing of more detailed `Debug` level messsages. Default is "" which only prints `Info` level messages |
|INHERIT\_JL\_SUMMARY_LEVEL| "debug", "info", "warn", "error", or "none"| logs the per-module summary message at the chosen level, or none at all. Default is "info". |

```@index
```

```@docs
@abstractbase
@implement

```