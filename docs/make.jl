using Documenter, Inherit

mymodules = [Inherit]
for m in mymodules
	DocMeta.setdocmeta!(m, :DocTestSetup, :(using $(Symbol(m))); recursive=true)
end
makedocs(
	sitename="Inherit.jl", 
	pages=[ "Home" => "index.md"],
	format = Documenter.HTML(prettyurls = false))
