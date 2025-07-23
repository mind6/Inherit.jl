#=
Utility functions which are used by this module but also useful generally. The symbols here can be exported and re-exported by other modules.
=#
"opposite of @test_throws"
macro test_nothrows(exp, args...)
	exp_str = string(exp)
	
	# Check if skip=true is in the arguments
	skip_condition = false
	for arg in args
		if isa(arg, Expr) && arg.head == :(=) && arg.args[1] == :skip
			skip_condition = arg.args[2]
			break
		end
	end
	
	quote
		# If skip condition is true, skip the test entirely
		local should_skip = $(esc(skip_condition))
		if should_skip
			@test true $(args...)  # Let @test handle the skip
		else
			local _test_result = true
			local _exception = nothing
			try
				$(esc(exp))
			catch ex
				_test_result = false
				_exception = ex
			end
			if _test_result
				@test true $(args...)
			else
				# Create a proper Test.Fail result with custom message
				local ts = get_testset()
				local custom_msg = "Expression $($exp_str) threw exception: $(_exception)"
				local fail_result = Fail(:test_nothrows, $exp_str, custom_msg, nothing, nothing, $(QuoteNode(__source__)), false)
				record(ts, fail_result)
			end
		end
	end
end