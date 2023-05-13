# Inherit.jl

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports the user to program with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

## Quick Start

```jldoctest
using Inherit

"abstract base type of Fruity objects"
@AbstractBase struct Fruit
	weight::Float32
	"declares an interface which must be implemented"
	function cost(fruit::Fruit, unitprice::Float32)::Float32 end
end

"concrete type which represents an apple, inheriting from Fruit"
@implement struct Apple <:Fruit 
	coresize::Int
end

"implements supertype's interface declaration `cost` for the type `Apple`"
function cost(apple::Apple, unitprice::Float32)::Float32 
	apple.weight * unitprice * (apple.coresize < 5 ? 1.1 : 1.0)
end

cost(Apple(3.0, 4), 1.0)

```

```@contents
```

```@index
```

```@autodocs
Modules = [Inherit]
```