using Test, Dates, DataFrames
using Revise, RPC
using Logging



# Enable debug level logging
# ENV["JULIA_DEBUG"] = "RPC"
# debug_logger = ConsoleLogger(stderr, Logging.Debug)
# global_logger(debug_logger)

@info "Starting RPC test..."

# Create a module for testing expression-based imports
module TestFunctions
	export add_expression, multiply_expression, greet_expression, failing_function, division_by_zero, nested_error
	
	function add_expression(a, b)
		return a + b
	end
	
	function multiply_expression(a, b)
		return a * b
	end
	
	function greet_expression(name)
		return "Hello from module, $(name)!"
	end

	# Functions that will raise errors for testing
	function failing_function()
		error("This function intentionally fails")
	end

	function division_by_zero()
		return 1 ÷ 0
	end

	function nested_error()
		# Call another function that will fail
		division_by_zero()
	end
end

# 1. Define some test functions on the server side (direct symbols)
function add(a, b)
	return a + b
end

function multiply(a, b)
	return a * b
end

function greet(name)
	return "Hello, $(name)!"
end

function get_date()
	return string(Dates.now())
end

function slow_operation(delay)
	sleep(delay)
	return "Completed after $delay seconds"
end

# Test function for array views
function test_array_view(view_data)
	# This function just returns the view it receives
	# so we can check what happens during serialization/deserialization
	return view_data
end

# Functions that will raise errors for testing
function error_function()
	error("Intentional error for testing")
end

function type_error_function()
	# This will cause a TypeError
	"string" + 5
end

function argument_error_function(required_arg)
	return required_arg
end

# After the test_array_view function, add:
# Test function for DataFrames
function test_dataframe(df)
	# Just return the DataFrame
	return df
end

# Test function for GroupedDataFrame
function test_grouped_df(gdf)
	# Just return the GroupedDataFrame
	return gdf
end

# Test function to return both DataFrame and GroupedDataFrame
function test_df_and_grouped(df, gdf)
	# Return both objects to check if relationship is preserved
	return (df=df, gdf=gdf)
end

# Register functions directly by symbol
RPCServer.@rpc_export add
RPCServer.@rpc_export multiply
RPCServer.@rpc_export greet
RPCServer.@rpc_export get_date
RPCServer.@rpc_export slow_operation
RPCServer.@rpc_export test_array_view
RPCServer.@rpc_export error_function
RPCServer.@rpc_export type_error_function
RPCServer.@rpc_export argument_error_function

# Register functions by expression
RPCServer.@rpc_export TestFunctions.add_expression
RPCServer.@rpc_export TestFunctions.multiply_expression
RPCServer.@rpc_export TestFunctions.greet_expression
RPCServer.@rpc_export TestFunctions.failing_function
RPCServer.@rpc_export TestFunctions.division_by_zero
RPCServer.@rpc_export TestFunctions.nested_error

# Add the new functions to the exported list:
RPCServer.@rpc_export test_dataframe
RPCServer.@rpc_export test_grouped_df
RPCServer.@rpc_export test_df_and_grouped

### all @rpc_export calls above must be added before starting the server, otherwise you'll get world age errors ###

# 2. Start the server
@info "Starting RPC server..."

RPCServer.start_server()

sleep(1)
# 3. Connect with the client
@info "Connecting client..."
RPCClient.connect()


# Add the new functions to the imported list:
RPCClient.@rpc_import test_dataframe
RPCClient.@rpc_import test_grouped_df
RPCClient.@rpc_import test_df_and_grouped


# 4. Import remote functions
# Import symbol-based functions
RPCClient.@rpc_import add
RPCClient.@rpc_import multiply
RPCClient.@rpc_import greet
RPCClient.@rpc_import get_date
RPCClient.@rpc_import slow_operation
RPCClient.@rpc_import test_array_view
RPCClient.@rpc_import error_function
RPCClient.@rpc_import type_error_function
RPCClient.@rpc_import argument_error_function

# Import expression-based functions 
RPCClient.@rpc_import TestFunctions.add_expression
RPCClient.@rpc_import TestFunctions.multiply_expression
RPCClient.@rpc_import TestFunctions.greet_expression
RPCClient.@rpc_import TestFunctions.failing_function
RPCClient.@rpc_import TestFunctions.division_by_zero
RPCClient.@rpc_import TestFunctions.nested_error

# 5. Call the remote functions
@info "Testing remote function calls..."


# Add this test case before the "6. Clean up" section:
# Test DataFrame and GroupedDataFrame serialization
@testset "RPC test - DataFrame and GroupedDataFrame serialization" begin
	# Create a test DataFrame
	df = DataFrame(
		id = [1, 2, 3, 4, 5, 1, 2],
		group = ["A", "A", "B", "B", "C", "C", "C"],
		value = [10, 20, 30, 40, 50, 60, 70]
	)
	
	# Create a GroupedDataFrame based on it
	gdf = groupby(df, :group)
	
	@info "Original DataFrame and GroupedDataFrame types:"
	@info "DataFrame type: $(typeof(df))"
	@info "GroupedDataFrame type: $(typeof(gdf))"
	
	# Test 1: Send both separately and get them back
	@info "Test 1: Sending DataFrame and GroupedDataFrame separately"
	df_returned = remote_test_dataframe(df)
	gdf_returned = remote_test_grouped_df(gdf)
	
	@info "Returned types:"
	@info "Returned DataFrame type: $(typeof(df_returned))"
	@info "Returned GroupedDataFrame type: $(typeof(gdf_returned))"
	
	# Test 2: Send both together and get them back
	@info "Test 2: Sending both DataFrame and GroupedDataFrame together"
	result = remote_test_df_and_grouped(df, gdf)
	df2_returned = result.df
	gdf2_returned = result.gdf
	
	@info "Returned types from combined call:"
	@info "Returned DataFrame type: $(typeof(df2_returned))"
	@info "Returned GroupedDataFrame type: $(typeof(gdf2_returned))"
	
	# Test if returned objects contain the same data
	@test df == df_returned
	@test keys(gdf) == keys(gdf_returned)
	
	# Test if the relationship between DataFrame and GroupedDataFrame is preserved
	# Modify the returned DataFrame and check if GroupedDataFrame reflects the change
	df_returned[1, :value] = 999
	
	@info "Original DataFrame after modification:"
	@info df
	@info "Returned DataFrame after modification:"
	@info df_returned
	@info "First group in returned GroupedDataFrame after DataFrame modification:"
	@info gdf_returned[1]
	
	# Check if the GroupedDataFrame reflects the change in the DataFrame
	@warn "DataFrame and GroupedDataFrame sent separately WILL NOT be linked"
	@test ("A",) in keys(gdf_returned)
	group_a = gdf_returned[("A",)]
	@test group_a.value[1] == 10
	
	# Test same for objects returned together
	@warn "DataFrame and GroupedDataFrame sent together WILL be linked"
	df2_returned[2, :value] = 888
	@test ("A",) in keys(gdf2_returned)
	group_a = gdf2_returned[("A",)]
	@test group_a.value[2] == 888
end


@testset "RPC test - direct symbols" begin
	# Basic arithmetic
	@test remote_add(10, 20) == 30
	@test remote_multiply(5, 6) == 30

	# String operations
	@test remote_greet("Julia") == "Hello, Julia!"
end

@testset "RPC test - module expressions" begin
	# Basic arithmetic from module
	@test remote_add_expression(10, 20) == 30
	@test remote_multiply_expression(5, 6) == 30

	# String operations from module
	@test remote_greet_expression("Julia") == "Hello from module, Julia!"
end

# Get current time
date_str = remote_get_date()
@info "Current date from server: $date_str"

# Test concurrent calls
@info "Testing concurrent calls..."
tasks = []
for i in 1:5
	t = @async begin
		result = remote_slow_operation(0.5)
		@info "Task $i result: $result"
		result
	end
	push!(tasks, t)
end

results = fetch.(tasks)
@info "All concurrent tasks completed"
@test length(results) == 5

# Test array view serialization
@testset "RPC test - array view serialization" begin
	original_array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	array_view = view(original_array, 3:7)
	
	# Send the view to the server and get it back
	returned_data = remote_test_array_view(array_view)
	
	# Check if we got back a view or a copy
	@info "Original view type: $(typeof(array_view))"
	@info "Returned data type: $(typeof(returned_data))"
	@test array_view == returned_data
	# Test if the data values match
	@test returned_data == [3, 4, 5, 6, 7]
	
	# Modify the original array to see if the returned data was a view or a copy
	original_array[5] = 100
	@info "Original array after modification: $original_array"
	@info "Original view after modification: $array_view"
	@info "Returned data after modification: $returned_data"
	
	# If returned_data was still a view onto original_array, it would reflect the change
	# If it's a copy, it would remain unchanged
	@test returned_data[3] != 100
end

# Test error handling and WrappedError functionality
@testset "RPC error handling - WrappedError" begin
	# Test basic error function
	@test_throws RPC.WrappedError remote_error_function()
	
	# Test with a type error
	@test_throws RPC.WrappedError remote_type_error_function()
	
	# Test with missing argument 
	@test_throws RPC.WrappedError remote_argument_error_function()
	
	# Test module-based error functions
	@test_throws RPC.WrappedError remote_failing_function()
	
	# Test division by zero
	@test_throws RPC.WrappedError remote_division_by_zero()
	
	# Test error propagation through call stack
	@test_throws RPC.WrappedError remote_nested_error()
	
	# Test error containment and message format
	try
		remote_error_function()
	catch e
		@test e isa RPC.WrappedError
		@test e.msg == "Error executing function $(RPC.create_function_key(error_function))"
		@test e.cause isa ErrorException
		@test e.cause.msg == "Intentional error for testing"
		@test !isempty(e.backtrace) # Ensure backtrace is captured
	end
	
	# Test division by zero error details
	try
		remote_division_by_zero()
	catch e
		@test e isa RPC.WrappedError
		@test e.cause isa DivideError
		@test !isempty(e.backtrace)
	end
	
	# Test nested error stack trace
	try
		remote_nested_error()
	catch e
		@test e isa RPC.WrappedError
		@test e.cause isa DivideError
		@test !isempty(e.backtrace)
		
		# Convert the error to string to test showerror
		err_str = sprint(showerror, e)
		@test contains(err_str, "Error executing function")
		@test contains(err_str, "Caused by:")
		@test contains(err_str, "Original stacktrace:")
	end
end

# 6. Clean up
@info "Disconnecting client..."
RPCClient.disconnect()

@info "Stopping server..."
RPCServer.stop_server()

@info "RPC test completed successfully!" 