cd(joinpath(@__DIR__, ".."))
@show pwd()

ENV["JULIA_DEBUG"] = "Inherit"
using Pkg
Pkg.activate(".")
Pkg.precompile(["Inherit", "PkgTest1"])
begin
	@time using Inherit
	@time using PkgTest1 # should take 4ms in same session, 1.5ms in new session
end
