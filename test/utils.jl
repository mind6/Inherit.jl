export @test_nothrows
import Test
"opposite of @test_throws"
macro Test.test_nothrows(exp, args...)
	try
		__module__.eval(exp)
		:(@test true $(args...))
	catch e
		showerror(stderr, e, catch_backtrace())
		:(@test false $(args...))
	end
end