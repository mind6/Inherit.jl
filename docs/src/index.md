# Introduction 

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

# Quick Start

Use `@abstractbase` to declare an abstract supertype, and use `@implement` to inherit from such a type. Standard `struct` syntax is used.

```jldoctest
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
## The module `__init__()` function
## The `@postinit` macro
## Changing the reporting level
 
By default, module `__init__()` writes a summary message at the `info` log level. You change this by setting `ENV["INHERIT_JL_SUMMARY_LEVEL"]` to one of `["debug", "info", "warn", "error", "none"]`

# Limitations
## Multiple inheritance

```@contents
```

```@index
```

```@autodocs
Modules = [Inherit]
```