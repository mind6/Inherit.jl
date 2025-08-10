# AGENTS

This repository hosts the Inherit.jl package. When working on tasks here, please:

- Search the codebase with `rg` rather than `grep -R`.
- Run the test suite against supported Julia versions before committing:
  - `julia +1.12 --project=. test/runtests.jl`
  - `julia +1.11 --project=. test/runtests.jl`
  - `julia +1.10 --project=. test/runtests.jl`
  If packages are missing for a version, run `julia +VERSION --project=. -e 'using Pkg; Pkg.instantiate()'` first.
- Commit directly to the main branch; do not create new branches.
- Include relevant file and test output citations in final summaries.

