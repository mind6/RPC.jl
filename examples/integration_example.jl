"""
Example of integrating the RPC system with an existing package.

This demonstrates:
1. Creating a module with existing functionality
2. Extending it with RPC capabilities
3. Showing how to use it from a client
"""

using Dates, Random
using Revise
import RPC: RPCServer, RPCClient


# First, let's create a simple module that we want to expose via RPC
module MathUtils

export add, subtract, multiply, divide, compute_statistics

function add(a, b)
	return a + b
end

function subtract(a, b)
	return a - b
end

function multiply(a, b)
	return a * b
end

function divide(a, b)
	if b == 0
		error("Division by zero")
	end
	return a / b
end

function compute_statistics(numbers)
	if isempty(numbers)
		return (min=nothing, max=nothing, mean=nothing, count=0)
	end
	
	return (
		min=minimum(numbers),
		max=maximum(numbers),
		mean=sum(numbers) / length(numbers),
		count=length(numbers)
	)
end

end # module MathUtils

# Now let's create a module that extends MathUtils with RPC capabilities
module RemoteMathUtils

using ..MathUtils
using ..RPCServer

# Register all exported functions from MathUtils
RPCServer.@rpc_export MathUtils.add
RPCServer.@rpc_export MathUtils.subtract
RPCServer.@rpc_export MathUtils.multiply
RPCServer.@rpc_export MathUtils.divide
RPCServer.@rpc_export MathUtils.compute_statistics

# Start the RPC server and register MathUtils functions
function start_server(host="127.0.0.1", port=8081)
	
	# Start the RPC server
	RPCServer.start_server(host, port)
	@info "RemoteMathUtils server started on $host:$port"
end

function stop_server()
	RPCServer.stop_server()
	@info "RemoteMathUtils server stopped"
end

end # module RemoteMathUtils

# Client code - this would typically be in a separate file/package
module MathClient

using ..RPCClient
using ..MathUtils
# Re-export the functions so users don't need to qualify them
export add, subtract, multiply, divide, compute_statistics

# Import the remote functions
RPCClient.@rpc_import MathUtils.add
RPCClient.@rpc_import MathUtils.subtract
RPCClient.@rpc_import MathUtils.multiply
RPCClient.@rpc_import MathUtils.divide
RPCClient.@rpc_import MathUtils.compute_statistics
	
# Connect to the MathUtils server
function connect(url="ws://127.0.0.1:8081")
	RPCClient.connect(url)
	@info "Connected to MathUtils server"

end

function disconnect()
	RPCClient.disconnect()
	@info "Disconnected from MathUtils server"
end

# Example usage
function run_example()
	# Connect the client
	@info "Connecting client..."
	MathClient.connect()
	

	
	@info "Testing remote function calls..."
	
	# Basic operations
	@info "10 + 5 = $(remote_add(10, 5))"
	@info "10 - 5 = $(remote_subtract(10, 5))"
	@info "10 * 5 = $(remote_multiply(10, 5))"
	@info "10 / 5 = $(remote_divide(10, 5))"
	
	# Try an operation that might fail
	try
		result = remote_divide(10, 0)
		@info "10 / 0 = $result"  # This should not execute
	catch e
		@info "Caught expected error: $e"
	end
	
	# Generate some random data and compute statistics
	random_data = rand(1:100, 20)
	@info "Random data: $random_data"
	stats = remote_compute_statistics(random_data)
	@info "Statistics: min=$(stats.min), max=$(stats.max), mean=$(stats.mean), count=$(stats.count)"
	
	# Test concurrent calls
	@info "Testing concurrent calls..."
	tasks = []
	for i in 1:5
		t = @async begin
			a = rand(1:100)
			b = rand(1:100)
			result = remote_add(a, b)
			@info "Task $i: $a + $b = $result"
			return result
		end
		push!(tasks, t)
	end
	
	results = fetch.(tasks)
	@info "All concurrent tasks completed with results: $results"
	
	# Clean up
	MathClient.disconnect()
	
	@info "Integration example completed successfully"
end

end # module MathClient

using .RemoteMathUtils
using .MathClient

# Start the server
@info "Starting RemoteMathUtils server..."
RemoteMathUtils.start_server()
	
# Run the example if this script is executed directly
MathClient.run_example()

# Stop the server
RemoteMathUtils.stop_server()
