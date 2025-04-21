using Test, Dates
using Revise, RPC
using Logging

# Enable debug level logging
ENV["JULIA_DEBUG"] = "RPC"
debug_logger = ConsoleLogger(stderr, Logging.Debug)
global_logger(debug_logger)

@info "Starting RPC test..."

# Create a module for testing expression-based imports
module TestFunctions
	export add_expression, multiply_expression, greet_expression
	
	function add_expression(a, b)
		return a + b
	end
	
	function multiply_expression(a, b)
		return a * b
	end
	
	function greet_expression(name)
		return "Hello from module, $(name)!"
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

# 2. Start the server
@info "Starting RPC server..."
# Register functions directly by symbol
RPCServer.@rpc_export add
RPCServer.@rpc_export multiply
RPCServer.@rpc_export greet
RPCServer.@rpc_export get_date
RPCServer.@rpc_export slow_operation

# Register functions by expression
RPCServer.@rpc_export TestFunctions.add_expression
RPCServer.@rpc_export TestFunctions.multiply_expression
RPCServer.@rpc_export TestFunctions.greet_expression

RPCServer.start_server()

sleep(1)
# 3. Connect with the client
@info "Connecting client..."
RPCClient.connect()

# 4. Import remote functions
# Import symbol-based functions
RPCClient.@rpc_import add
RPCClient.@rpc_import multiply
RPCClient.@rpc_import greet
RPCClient.@rpc_import get_date
RPCClient.@rpc_import slow_operation

# Import expression-based functions 
RPCClient.@rpc_import TestFunctions.add_expression
RPCClient.@rpc_import TestFunctions.multiply_expression
RPCClient.@rpc_import TestFunctions.greet_expression

# 5. Call the remote functions
@info "Testing remote function calls..."

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

# 6. Clean up
@info "Disconnecting client..."
RPCClient.disconnect()

@info "Stopping server..."
RPCServer.stop_server()

@info "RPC test completed successfully!" 