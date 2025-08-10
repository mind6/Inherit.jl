[![Build Status](https://github.com/mind6/Inherit.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mind6/Inherit.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/mind6/Inherit.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/mind6/Inherit.jl)

# Developers/Raven/DataAnnotation.tech

The environment setup README is [here](file:///README_setup.md)

# Introduction 

Inherit.jl is used to inherit fields and interface definitions from a supertype. It supports programming with an **object-oriented flavor** in Julia, whenever this is more appropriate than developing under traditional Julia patterns. 

**Fields** defined in a supertype are automatically inherited by each subtype, and **method declarations** are checked for each subtype's implementation. An **inheritance hierachy** across multiple modules is supported. To accomplish this, macro processing is used to construct **native Julia types**, which allows the the full range of Julia syntax to be used in most situations.

# Quick Start

Use `@abstractbase` to declare an abstract supertype, and use `@implement` to inherit from such a type. Standard `struct` syntax is used.

```julia
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
```
```
6.0
```
Note that the definition of `cost` function inside of `Fruit` is interpreted as an interface declaration; it does not result in a method being defined.

!!! info 
	What this declaration means is that when invoking the `cost` function, passing an object which is a subtype of `Fruit` (declared with the `@implement` macro) to the `fruit::Fruit` parameter must be able to dispatch to some method instance. This is verified when a module is first loaded. 

# Interaction with modules

An object oriented programming style can be useful to applications that span across multiple modules. Even though __Inherit.jl__ can be used inside of scripts, its true usefulness is to assert __common interfaces__ shared by different data types from different modules. __Verification__ of method declarations take place in the `__init__()` function of the module which the implementing type belongs to (i.e. where the `@implement` macro is used).

## The module `__init__()` function

The specially named module-level (i.e. top-level) function `__init__()` is called after the module has been fully loaded by Julia. If an interface definition has not been met, an exception will be thrown.

```julia
module M1
	using Inherit
	@abstractbase struct Fruit
		weight::Float64
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	@implement struct Apple <: Fruit end
	@implement struct Orange <: Fruit end
	@implement struct Kiwi <: Fruit end

	function cost(fruit::Union{Apple, Kiwi}, unitprice::Float64) 
		1.0 
	end
end
```
```
ERROR: InitError: ImplementError: subtype M1.Orange missing Tuple{typeof(M1.cost), M1.Orange, Float64} declared as:
function cost(fruit::Fruit, unitprice::Float64)
[...]
```
Upon loading module `M1`, Inherit.jl throws an `ImplementError` from the `__init__()` function, telling you that it's looking for a method signature that can dispatch `cost(::M1.Orange, ::Float64)`. It makes no complaints about `Apple` and `Kiwi` because their dispatch can be satisfied.

## The `@postinit` macro

The presence of an `@abstractbase` or `@implement` macro causes Inherit.jl to generate and __overwrite__ the module's `__init__()` function. To execute your own module initialization code, the `@postinit` macro is available. It accepts a function as argument and registers that function to be executed after `__init__()`. Multiple occurrences of `@postinit` will result in each function being called successively.

# Putting it all together

Let's demonstrate `@postinit` as well as other features in a more extended example.

```julia
module M1
	using Inherit

	@abstractbase struct Fruit
		weight::Float64
		"docstrings of method declarations are appended at the end of method docstrings"
		function cost(fruit::Fruit, unitprice::Float64) end
	end
	"this implementation satisfies the interface declaration for all subtypes of Fruit"
	function cost(item::Fruit, unitprice::Real)
		unitprice * item.weight
	end		
end

module M2
	using Inherit
	import ..M1

	@abstractbase struct Berry <: M1.Fruit
		"
		In a declaration, the supertype can appear in a variety of positions. 
		A supertype argument can be matched with itself or a __narrower__ type.
		Supertypes inside containers must be matched with itself or a __broader__ type.
		"
		function pack(time::Int, ::Berry, bunch::Vector{Berry}) end

		"
		However, if you prefix the supertype with `<:`, it becomes a ranged parameter. You can match it with a ranged subtype parameter.
		"
		function move(::Vector{<:Berry}, location) end
	end

	@implement struct BlueBerry <: Berry end

	"
	The implementing method's argument types can be broader than the interface's argument types.
	Note that `AbstractVector{<:BlueBerry}` will not work in the 3rd argument, because a `Vector{Berry}` argument will have no dispatch.
	"
	function pack(time::Number, berry::BlueBerry, bunch::AbstractVector{<:M1.Fruit}) 
		println("packing things worth \$$(cost(first(bunch), 1.5) + cost(berry, 1.5))")
	end

	"
	The subtype `BlueBerry` can be used in a container, because it's a ranged parameter. Make sure nested containers are all ranged parameters; otherwise, the interface cannot be satisfied.
	"
	function move(bunch::Vector{<:BlueBerry}, location) 
		println("moving $(length(bunch)) blueberries to $location")
	end

	@postinit function myinit()
		println("docstring of imported `cost` function:\n", @doc cost)
		pack(0, BlueBerry(1.0), [BlueBerry(2.0)])
		move([BlueBerry(1.0), BlueBerry(2.0)], "the truck")
	end
end
```
```
[ Info: Inherit.jl: processed M1 with 1 supertype having 1 method requirement. 0 subtypes were checked with 0 missing methods.
[ Info: Inherit.jl: processed M2 with 1 supertype having 3 method requirements. 1 subtype was checked with 0 missing methods.
docstring of imported `cost` function:
this implementation satisfies the interface declaration for all subtypes of Fruit
 
docstrings of method declarations are appended at the end of method docstrings

packing things worth $4.5
moving 2 blueberries to the truck
```

We can make a few observations regarding the above example:
- A __summary message__ is printed after each module is loaded, showing Inherit.jl is active.
- __Multiple levels of inheritance__ is possible across multiple modules.
- Method definitions __are quite flexible__. In a method declaration, you can name a supertype anywhere that's valid in Julia, and it will be checked for proper dispatch of subtypes.
- The function `M1.cost` was __automatically imported__ into module `M2`. The function still lives in module `M1` together with its method instances, but it is available in `M2` through the symbol `cost`.
  - While not shown in this example, you can __extend `M1.cost`__ by writing `function cost(...) ... end` in module `M2`
- __Docstrings are preserved__. Docstring for method declarations are added to the end of any  method docstrings. 

!!! info 
	When implementing a method declaration, supertypes inside of containers like (e.g. Pair, Vector, Dict) may not be substituted with a subtype, because Julia's type parameters are invariant. However, a ranged supertype parameter (prefixed with <:) can be substituted with a ranged subtype.

## Changing the reporting level

To have module `__init__()` log an error message instead of throwing an exception, add `setreportlevel(ShowMessage)` near the front of the module. You can also disable interface checking altogether with `setreportlevel(SkipInitCheck)`

By default, module `__init__()` writes its summary message at the `Info` log level. You can change this by setting `ENV["INHERIT_JL_SUMMARY_LEVEL"]` to one of `["debug", "info", "warn", "error", "none"]`.

# Limitations

Parametric types are supported; all type parameters must match exactly when inheriting.

Methods are examined only for their positional arguments. Inherit.jl has no special knowledge of keyword arguments, but this may improve in the future.

Constructor inheritance is supported via the `@virtualnew` macro.

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

## See [documentation](https://mind6.github.io/Inherit.jl/) for API details.
