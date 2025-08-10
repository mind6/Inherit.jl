# Inherit.jl Overview for Newcomers

## Purpose
Inherit.jl adds an object-oriented flavor to Julia by letting you define “abstract base” types that carry both data fields and required method signatures, and then implement concrete subtypes that inherit those fields and must satisfy the declared interfaces. All of this is done with macros, so the resulting types are still native Julia structs.

---

## Repository Structure

| Path | Role |
|------|------|
| `Project.toml` | Package metadata and dependencies (only `MacroTools`; optional extensions for `Distributed` and `Test`). |
| `src/` | Core library source files. |
| `ext/` | Optional extensions (`DistributedExt.jl`, `TestExt.jl`). |
| `docs/` | Documentation (Documenter.jl format). |
| `test/` | Test suite and example packages. |

### Key Source Files (`src/`)

- **`Inherit.jl`** – Main module.
  - Exports the macros `@abstractbase`, `@implement`, `@verify_interfaces`, and various reporting utilities.
  - Sets up compile‑time databases (`setup_module_db`, `CompiletimeModuleInfo`) to track declared fields, constructors, and required methods.

- **`abstractbase.jl`** – Implements `@abstractbase`.
  - Parses type definitions, defines abstract types, records fields/method declarations, and inherits metadata from supertypes.

- **`constructors.jl`** – Transforms constructors.
  - Handles `new()` and a `super()` placeholder so subclasses can call parent constructors and merge field tuples.

- **`types.jl`** – Shared data structures.
  - Includes `TypeSpec` (fields, mutability, type parameters), `MethodDeclaration`, `ConstructorDefinition`, and error types.

- **`utils.jl` / `publicutils.jl`** – Helper utilities.
  - AST manipulation, building import expressions, color constants, `isprecompiling`, and a `@test_nothrows` macro (re-exported in `ext/TestExt.jl`).

### Extensions (`ext/`)
- **`DistributedExt.jl`** – Provides `warmup_import_package` to pre-load packages on remote workers using `Distributed`.
- **`TestExt.jl`** – Adds `@test_nothrows` (the opposite of `@test_throws`) with optional skip logic.

### Documentation (`docs/`)
- `index.md` is an extended tutorial with quick start, multi-module examples, and limitations.
- `design_notes.md` discusses architectural choices and future plans.

### Tests (`test/`)
- Organized by feature: constructors, parameterized structs, traits, utilities, etc.
- `PkgTest*` directories hold mini-packages used to test cross-module inheritance behavior.

---

## Important Concepts

1. **Macros as the API**
   - `@abstractbase` declares an abstract type plus interface requirements (fields & method signatures).
   - `@implement` defines a concrete subtype, inherits fields, and checks that required methods exist.
   - `@verify_interfaces` optionally checks at compile time that all interfaces were met.

2. **Compile-time Metadata**
   - Each module using Inherit.jl gets a `CompiletimeModuleInfo` record tracking known supertypes, subtypes, required methods, and constructor info.
   - All interface verification now occurs at compile time—there is no module `__init__` step.

3. **Constructor Handling**
   - Abstract constructors are rewritten to return tuples of fields.
   - Concrete constructors can call `super()`; this is converted into a spread of the parent’s constructor tuple.

4. **Reporting Levels**
   - `setreportlevel(ThrowError | ShowMessage | SkipInitCheck)` controls how missing implementations are reported during compilation.

5. **Extensions & Utilities**
   - `warmup_import_package` aids benchmarking by importing packages on a worker.
   - `@test_nothrows` helps ensure code segments run without exceptions in tests.

---

## Getting Started

1. **Read the Documentation**
   - Start with `docs/src/index.md` for a guided tour and examples.

2. **Experiment in the REPL**
   - Create simple modules using `@abstractbase` and `@implement`.
   - Observe how interface checks happen during compilation.

3. **Review the Tests**
   - Files in `test/` show idiomatic usage, including constructor inheritance, parameterized types, and trait-like extensions.

4. **Explore the Source**
   - `abstractbase.jl` and `constructors.jl` are key if you want to understand or extend the macros.
   - `utils.jl` demonstrates macro-based AST transformations, useful if you plan to contribute.

---

## Suggested Next Steps

- **Macro Tools**: Learn `MacroTools` (the only dependency) to understand how the macros transform Julia code.
- **Julia’s type system**: Familiarity with multiple dispatch and compile-time macros is crucial.
- **Contributing**: Start with smaller utilities or documentation improvements; then explore enhancements like multiple inheritance or keyword-argument support.
- **Testing & Benchmarking**: The `test/` suite and `DistributedExt` show how to structure cross-module tests and warm up package compilation.

---

With this overview, you should be ready to navigate the codebase, experiment with the macros, and dive deeper into Julia’s metaprogramming capabilities. Happy hacking!
