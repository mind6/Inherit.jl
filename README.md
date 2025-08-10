[![Build Status](https://github.com/mind6/Inherit.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/mind6/Inherit.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/mind6/Inherit.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/mind6/Inherit.jl)

# Inherit.jl

Inherit.jl provides macros for inheriting fields and interface declarations from a supertype.
The macros generate native Julia types so you can work with familiar syntax while ensuring
that required methods are implemented.

## Quick start

```julia
using Inherit

@abstractbase struct Fruit
    weight::Float64
    function cost(fruit::Fruit, unitprice::Float64) end
end

@implement struct Apple <: Fruit
    coresize::Int
end

function cost(apple::Apple, unitprice::Float64)
    apple.weight * unitprice * (apple.coresize < 5 ? 2.0 : 1.0)
end

println(cost(Apple(3.0, 4), 1.0))
# output
6.0
```

Further resources:

- [Project overview](OVERVIEW.md)
- [Documentation](docs/src/index.md)
- [Release notes](release_notes.md)
- [Environment setup](README_setup.md)

