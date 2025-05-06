"""
Cross-process RPC example with automatic server shutdown (Windows-specific version).

This example demonstrates:
1. Running the RPC server in a separate Julia process
2. Automatic server shutdown after 5 seconds
3. Error handling that works across process boundaries
4. Proper handling of Windows paths
5. Using the same module for both client and server
"""

module CrossProcessClient

using Dates, Random
import RPC: RPCClient, RPCServer

# Define the functions that will be shared between client and server
function add(a, b)
	return a + b
end

function multiply(a, b)
	return a * b
end

function divide_by_zero()
	return 1 ÷ 0
end

function normal_error()
	error("This is an intentional error for testing")
end

# Client-side functionality
# Import the remote functions
RPCClient.@rpc_import CrossProcessClient.add
RPCClient.@rpc_import CrossProcessClient.multiply
RPCClient.@rpc_import CrossProcessClient.divide_by_zero
RPCClient.@rpc_import CrossProcessClient.normal_error

function run_client_example()
	@info "Starting client example..."
	
	# Connect to the server
	@info "Connecting to RPC server..."
	RPCClient.connect("ws://127.0.0.1:8082")  # Different port to avoid conflicts
	
	
	# Test basic functions
	@info "Testing basic functions..."
	@info "10 + 20 = $(remote_add(10, 20))"
	@info "5 * 6 = $(remote_multiply(5, 6))"
	
	# Test error handling - normal error
	@info "Testing normal error handling..."
	try
		remote_normal_error()
	catch e
		@info "Caught expected error from server process:"
		@error e
	end
	
	# Test error handling - divide by zero
	@info "Testing divide by zero error handling..."
	try
		remote_divide_by_zero()
	catch e
		@info "Caught expected divide by zero error from server process:"
		@error e
	end
	
	# Clean up
	RPCClient.disconnect()
	@info "Client example completed"
end

# Server-side functionality
# Register the functions
RPCServer.@rpc_export CrossProcessClient.add
RPCServer.@rpc_export CrossProcessClient.multiply
RPCServer.@rpc_export CrossProcessClient.divide_by_zero
RPCServer.@rpc_export CrossProcessClient.normal_error

function run_server()
	@info "Server process started"
	
	
	# Start the server
	@info "Starting RPC server process on port 8082..."
	RPCServer.start_server("127.0.0.1", 8082)
	
	# Set up automatic shutdown after 5 seconds
	@info "Server will automatically shut down after 5 seconds"
	@async begin
		sleep(5)
		@info "Automatic shutdown triggered"
		RPCServer.stop_server()
		@info "Server shutdown complete"
	end
	
	# Keep the process alive until the server is closed
	wait(RPCServer.server)
	
	@info "Server process exiting"
end

end # module CrossProcessClient

# Function to start the server in a separate process (Windows-specific)
function start_server_process()
	# Get the current script path
	current_script = @__FILE__
	
	# Ensure Windows path format
	current_script = replace(current_script, "/" => "\\")
	
	# Start the server process with Windows-specific command
	# Use full path to julia executable
	julia_path = joinpath(dirname(dirname(Base.julia_cmd().exec[1])), "bin", "julia.exe")
	
	@info "Starting server in a separate visible terminal window"
	@info "Using Julia at: $(julia_path)"
	
	# Start a new visible terminal window
	# Chain the Julia command with a pause command to keep the window open
	server_process = run(`cmd /c start "RPC Server" cmd /c ""$(julia_path)" $(current_script) server & pause"`, wait=false)
	
	return server_process
end

# Main execution
function run_client()
	# Start the server in a separate process
	server_process = start_server_process()
	
	# Give the server time to start up
	@info "Waiting for server to start..."
	sleep(2)
	
	# Run the client example
	CrossProcessClient.run_client_example()
	
	@info "Example completed"
end

# Entry point - check if we should run as client or server
if length(ARGS) > 0 && ARGS[1] == "server"
	CrossProcessClient.run_server()
else
	run_client()
end 