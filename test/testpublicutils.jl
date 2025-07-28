using Inherit, Test

@testset "test_nothrows basic functionality" begin
	# Test successful case
	@test_nothrows 2 + 2  # This should pass
	
	# Test failure case - we expect this to fail and want to verify the message
	ts = Test.DefaultTestSet("expected_failure")
	Test.push_testset(ts)
	
	f() = error("test message")
	try
		@test_nothrows f()
	finally
		Test.pop_testset()
	end
	
	# Verify it failed as expected and captured the message
	@test length(ts.results) == 1
	@test ts.results[1] isa Test.Fail
	@test occursin("test message", ts.results[1].data)
end

@testset "test_nothrows skip functionality" begin
	# Test that skip=true actually skips the test
	ts = Test.DefaultTestSet("skip_test")
	Test.push_testset(ts)
	
	try
		@test_nothrows error("this should not execute") skip=true
	finally
		Test.pop_testset()
	end
	
	# Should have 1 result that is broken (skipped)
	@test length(ts.results) == 1
	@test ts.results[1] isa Test.Broken
end

