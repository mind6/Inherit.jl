# Design goals
# Technical approach
## Compile-time only
## Lookup of foreign module instances
We no longer use `__init__()` or any macro to self register a foreign module (one which defines a supertype used by the local module) with Inherit at its `fullname()`. Instead, module instances are found through `parentmodule(supertype)`.
## No longer auto-imports foreign functions
Since a foreign module may not share a root (such as Main) with the local module, it's very tricky and probably confusing to the user to construct an import path for the required foreign function. It's much better to let the user explicitly import the needed functions.

# Primary characteristics of the Julia system
## Macros
Run only at compile time. Returns an expression which gets compiled for runtime execution.

If you want to get exceptions at runtime, you need to return an expression that throws the exception. Directly raising exceptions from a macro causes the module to fail loading with LoadError. Use `return :(throw(...))` to have the exception evaluate at the caller.

You *can* catch such a load error by evaluating a module creating expression at the toplevel of another module:

```julia
	try
		eval(:(
			module FailingModule
				@error_throwing_macro
			end
		))
		@assert false
	catch e
		@assert e isa LoadError 
		@assert e.error isa MyError
		@assert contains(e.error.msg, "my error message")
	end
```

## eval

**Can** `Core.eval(module, expr)` at runtime into any module. **Cannot** evaluate into a closed module (basically any module other than the one being precompiled) at precompile time. However, you can eval into a submodule of the currently precompiled (open) module.

When you generate expressions to be eval'ed in a user module, make sure to explicitly reference library functions, so they do not inadvertently invoke functions defined in the user module.

## Precompilation

Whether or not we're precompiling is determined by:
```julia
Inherit.isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

```

Data and function instances obtained during precompilation persist into runtime. Module instances do not.

Since Julia 1.10, you cannot call `Base.delete_method()` at during precompilation.

## Performance
Module `__init__()` often has to be recompiled each time a module loaded. This will happen if this function or any function it calls uses eval or complex macros like @info, @debug etc. The performance hit is going to be like 400ms vs 4ms to load the module.

## Functions and method definitions

`typeof(f).name.mt` grows for each evaluation of method definition, even if it overwrites a previous definition. It is not the same as `methods(f)`

`Base.delete_method()` cannot be called at all during precompilation.

## Keyword arguments

A method's signature is defined by its positional arguments. Keyword arguments do not participate in method dispatch. A second method definition with same position arguments but different keyword arguments will ovewrite the first definition.

## Parametric types
A parametric type signature can be supertype of abstract type signature
	Tuple{typeof(f), Real} <: Tuple{typeof(f), T} where T<:Number

## Modules

You cannot delete symbols from a module. You can reassign some globals to `nothing`, but you cannot reassign functions or submodule references (they're defined as `const`).

### `@__MODULE__` and `__module__`

NOTE that only the quoted expression has access to the correct `@__MODULE__`. Any utility functions of Inherit.jl must receive this as a parameter, instead of invoking `@__MODULE__` directly.

## Documenter

`@doc` works at precompile time. It must be used with the expression that defines the function, not a function instance obtained after defining the function.

# Other characteristics of the Julia system

## MacroTools.postwalk
`MacroTools.striplines(ex)` is equivalent to:
```julia
	ex = MacroTools.prewalk(MacroTools.rmlines, ex) 
	ex |> dump
```
### Always returns a new expression tree
Under the hood `postwalk(f, x)` is defined via a tiny `walk` function that does this:

```julia
walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))

postwalk(f, x) = walk(x, x -> postwalk(f, x), f)
prewalk(f, x)  = walk(f(x), x -> prewalk(f, x), identity)
```

So for every `Expr` node it always constructs a new `Expr(...)` with the (recursively transformed) children and then applies `f` (for `postwalk`) to that. Even if nothing logically changed, each `Expr` in the tree is rebuilt as a fresh object; only non-`Expr` leaves (e.g., `Symbol`, `Int`) are passed through as-is unless `f` replaces them. In other words, structural equality is preserved when `f` is the identity, but object identity is not: e.g.

```julia
using MacroTools
ex = :(a + b)
new = postwalk(x -> x, ex)
new == ex        # true (structurally)
new === ex       # false (different Expr object)
```

The symbols `:a` and `:b` inside are interned, so those subnodes may be the same objects, but every `Expr` wrapper is newly allocated. ([news.ycombinator.com][1])

[1]: https://news.ycombinator.com/item?id=31828658&utm_source=chatgpt.com "An introduction to deep code-walking macros with Clojure (2013)"

