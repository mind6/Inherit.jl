module PkgTest4
using Inherit

init_fn::Union{Function, Nothing} = nothing

macro greet()
	if isprecompiling()
		@info("Hello macro! (precompiling)")
		global init_fn = eval(:(() -> println("I'm a function created inside a macro"))) #don't use @info in code that will be called from __init__()
	else
		@info("Hello macro! (not precompiling)")  #no problem with @info here
	end
end

function init_greet()
	if isprecompiling()
		println("Hello fn! (precompiling)")		#there's no compilation with println, but 200ms with @info even inside a function!
	else
		println("Hello fn! (not precompiling)")
	end
end

@greet

function __init__()
	init_greet()	#1.5ms no compilation with println, but very high with @info!
	init_fn()
	@greet()	# does nothing because the macro returns nothing
	# println(1 + 2)		#15ms
	# @info("PkgTest4.__init__")	#190ms
end

@info("bottom of file")

end # module PkgTest4
