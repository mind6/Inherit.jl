module DistributedExt

import Inherit: warmup_import_package, build_import_expr
using Distributed


"""
Uses Distributed.jl to call `import pkgname1, pkgname2, ...` on a worker to warm up the import process for the given packages.

This is useful for measuring package load times after precompilation. (It's not enough to call `Pkg.precompile`, which doesn't fully warm up the package import process until you call "import MyPackage")

Use the following idiom to load Inherit.jl (don't load it before Distributed.jl), or the interaction with Distributed.jl may cause compilation and affect your package load times:

```julia
using Distributed
pids = addprocs(1)
import Inherit: warmup_import_package  # or 'using Inherit'
rmprocs(pids)

```

"""
function warmup_import_package(pkgnames::Symbol...)
	local pids = addprocs(1)
	eval(:(@everywhere import Inherit)) 	# this is critical to allow the worker to load DistributedExt.jl -- it won't work if you do it in the @fetchfrom statement
	
	# it's not enough to call Pkg.precompile, it doesn't fully warm up the package import process until you call "import MyPackage"
	import_expr = build_import_expr(pkgnames...)
	@fetchfrom pids[1] Core.eval(Main, import_expr)  # must wait for the future or subsequent imports will proceed to compile on their own without waiting for the statement to finish -- it is not enough to rely on rmprocs to wait for the worker to finish.
	rmprocs(pids)	# waiting for worker to finish reduces conflict with subsequent import statements
	@info "warmup worker $(pids[1]) finished"
end
end