#=
Utility functions which are used by this module but also useful generally. The symbols here can be exported and re-exported by other modules.
=#
macro test_nothrows end

isprecompiling() = ccall(:jl_generating_output, Cint, ()) == 1

const GREEN = "\033[92m"
const BOLD = "\033[1m"
const END = "\033[0m"
const BLUE = "\033[94m"
