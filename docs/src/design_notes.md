# Characteristics of the Julia system
## MacroTools.postwalk
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

