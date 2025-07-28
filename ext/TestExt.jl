module TestExt

import Inherit: @test_nothrows
import Test: @test, record, get_testset, Fail

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
			local _backtrace = nothing
			try
				$(esc(exp))
			catch ex
				_test_result = false
				_exception = ex
				_backtrace = catch_backtrace()
			end
			if _test_result
				@test true $(args...)
			else
				# Create a proper Test.Fail result with exception message in data field
				local ts = get_testset()
				local exception_msg = string(_exception)
				
				# Format the backtrace as a string
				local bt_io = IOBuffer()
				Base.show_backtrace(bt_io, _backtrace)
				local bt_str = String(take!(bt_io))
				
				# Include both expression and exception in the displayed information
				local display_expr = "$($exp_str) threw exception: $exception_msg"
				# Create custom message to display the exception with backtrace
				local custom_message = "$($exp_str) threw exception: $exception_msg\nStacktrace:\n$bt_str"
				local fail_result = Fail(:test_nothrows, custom_message, display_expr, _exception, nothing, $(QuoteNode(__source__)), true)
				record(ts, fail_result)
			end
		end
	end
end

end