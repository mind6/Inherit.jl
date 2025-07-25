module PkgTest4
using Inherit

macro greet()
	if isprecompiling()
		@info("Hello macro! (precompiling)")
	else
		@info("Hello macro! (not precompiling)")
	end
end

function fn_greet()
	if isprecompiling()
		println("Hello fn! (precompiling)")		#no compilation with println, but very high with @info!
	else
		println("Hello fn! (not precompiling)")
	end
end

@greet

function __init__()
	fn_greet()	#1.5ms no compilation with println, but very high with @info!
	# @greet()	# does nothing!
	# println(1 + 2)		#15ms
	# @info("PkgTest4.__init__")	#190ms
end

@info("bottom of file")

end # module PkgTest4
