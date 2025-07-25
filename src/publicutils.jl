#=
Utility functions which are used by this module but also useful generally. The symbols here can be exported and re-exported by other modules.
=#

isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

macro test_nothrows end