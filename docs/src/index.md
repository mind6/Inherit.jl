# Introduction 

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

```@meta
DocTestSetup = quote
	import Inherit
	ENV["JULIA_DEBUG"] = ""
	ENV[Inherit.E_SUMMARY_LEVEL] = "info"
	@show ENV["JULIA_DEBUG"] 
end
```

# Quick Start

Use `@abstractbase` to declare an abstract supertype, and use `@implement` to inherit from such a type. Standard `struct` syntax is used.

```jldoctest mylabel
using Inherit

"abstract base type of Fruity objects"
@abstractbase struct Fruit
	weight::Float64
	"declares an interface which must be implemented"
	function cost(fruit::Fruit, unitprice::Float64) end
end

"
concrete type which represents an apple, inheriting from Fruit
it has two fields: `weight` and `cost`
"
@implement struct Apple <: Fruit 
	coresize::Int
end

"implements supertype's interface declaration `cost` for the type `Apple`"
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

```jldoctest mylabel
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
## The `@postinit` macro
## Changing the reporting level
 
By default, module `__init__()` writes a summary message at the `Info` log level. You can change this by setting `ENV["INHERIT_JL_SUMMARY_LEVEL"]` to one of `["debug", "info", "warn", "error", "none"]`.

# Limitations
## Multiple inheritance

## Syntax quirks
Use relative module reference such as 

```julia
module OtherModule
end

module MyModule
	using ..OtherModule
end
```

rather than 

```julia
module MyModule
	using Main.OtherModule
end
``` 
.

`Inherit.jl` will not look for `Main` to try to find `OtherModule`, because parent module `Main` isn't available to `MyModule` in some situations. 


# ```@contents
# ```

# ```@index
# ```

# ```@autodocs
# Modules = [Inherit]
# ```