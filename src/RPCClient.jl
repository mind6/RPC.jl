module RPCClient
import ..RPC: send_serialized, deserialize, WebSockets, FunctionName, create_function_key, WrappedError, ResultOrException, Result

export connect, disconnect, @rpc_import

# Structure to hold connection state
mutable struct Connection
	ws::Union{Nothing, WebSockets.WebSocket}
	task::Union{Nothing, Task}
	request_channel::Channel
	response_channels::Dict{UInt, Channel}
	is_connected::Bool
end

# Global connection
const connection = Connection(nothing, nothing, Channel{Any}(Inf), Dict{UInt, Channel}(), false)
request_processor = nothing

"""
Connects to an RPC server
"""
function connect(url="ws://127.0.0.1:8081")
	global connection
	
	if connection.is_connected
		@info "Already connected to RPC server"
		return
	end
	
	@debug "Initializing RPC client connection to $(url)"
	
	# Create a new request channel
	connection.request_channel = Channel{Any}(Inf)
	connection.response_channels = Dict{UInt, Channel}()
	
	# Start the client task
	connection.task = @async begin
		WebSockets.open(url) do ws
			connection.ws = ws
			connection.is_connected = true
			@info "Connected to RPC server at $(url)"
			
			# Start a task to process outgoing requests
			global request_processor = @async begin
				@debug "Starting request processor task"
				for request in connection.request_channel
					if request === nothing
						@debug "Request processor received shutdown signal"
						break
					end
					
					@debug "Sending request to server" request
					# Serialize and send the request
					send_serialized(ws, request)
				end
				@debug "Request processor task completed"
			end
			
			# Process incoming responses
			@debug "Starting response handler"
			for msg in ws
				try
					@debug "Received response from server"
					# Deserialize the response directly
					response = deserialize(IOBuffer(msg))
					
					if response isa Tuple && length(response) >= 2
						id = response[1]
						result = response[2]
						
						@debug "Processing response" id
						if haskey(connection.response_channels, id)
							@debug "Delivering response to waiting channel" id
							put!(connection.response_channels[id], result)
						else
							@error "Server returned an error" id result
						end
					else
						@warn "Invalid response format" response
					end
				catch e
					@error "Error processing response" exception=e catch_backtrace()
				end
			end
			@debug "Response handler completed"
			
			connection.is_connected = false
			@info "Disconnected from RPC server"
		end
	end
	
	# Wait for connection to establish or fail
	@debug "Waiting for connection to establish"
	t0 = time()
	while !connection.is_connected
		sleep(0.1)
		if istaskdone(connection.task) || (time() - t0 > 5.0)
			@debug "Connection attempt timed out or failed"
			error("Failed to connect to RPC server")
		end
	end
	@debug "Connection established successfully"
	
	return connection
end


"""
Disconnects from the RPC server
"""
function disconnect()
	global connection
	
	if !connection.is_connected
		@info "Not connected to RPC server"
		return
	end
	
	@debug "Initiating client disconnect"
	
	# Signal the request processing task to stop
	@debug "Sending shutdown signal to request processor"
	put!(connection.request_channel, nothing)
	
	# Close the WebSocket connection
	if connection.ws !== nothing
		@debug "Closing WebSocket connection"
		close(connection.ws)
		connection.ws = nothing
	end
	
	# Wait for the task to complete
	if connection.task !== nothing && !istaskdone(connection.task)
		@debug "Waiting for client task to complete"
		wait(connection.task)
	end
	
	connection.is_connected = false
	@info "Disconnected from RPC server"
end

"""
Calls a remote procedure on the server
"""
function call_remote(func_name::FunctionName, args...)
	global connection
	
	if !connection.is_connected
		error("Not connected to RPC server")
	end
	
	# Create a unique ID for this request
	id = UInt(rand(UInt32))
	@debug "Creating remote call" id func_name args
	
	# Create a channel for the response
	@debug "Creating response channel" id
	response_channel = Channel{Any}(1)
	connection.response_channels[id] = response_channel
	
	# Send the request with ID
	@debug "Queuing request" id func_name
	put!(connection.request_channel, (id, func_name, args...))
	
	# Wait for the response
	@debug "Waiting for response" id
	response = take!(response_channel)
	@debug "Received response" id response
	
	# Clean up
	@debug "Cleaning up response channel" id
	delete!(connection.response_channels, id)
	
	# Handle the response based on its type
	if response isa Result
		@debug "Remote call completed successfully" id
		return response.value
	elseif response isa WrappedError
		@debug "Remote call resulted in error" id response
		throw(response)  # This will use the custom Base.showerror method
	elseif response isa String && startswith(response, "Error: ")
		# Handle legacy error format for compatibility
		@debug "Remote call resulted in error (legacy format)" id response
		error(response[8:end])
	else
		@debug "Remote call completed with direct value" id
		return response
	end
end

"""
Given a function expression [ModulePath].function_name, defines a function called remote_[function_name] that calls the function on the RPC server.
"""
macro rpc_import(func_expr)
	# For expressions like MathUtils.add, extract the last part as the function name
	# For symbols, use the symbol itself
	func_str = string(func_expr)
	
	# Extract the simple function name for creating the remote function
	simple_name = if func_expr isa Symbol
		func_expr
	else
		# For expressions like A.B.C, get just the C part
		parts = split(func_str, ".")
		Symbol(parts[end])
	end
	
	# Create the remote function name (e.g., remote_add)
	remote_func_sym = esc(Symbol("remote_", simple_name))
	
	return quote
		# Evaluate the function expression in the caller's module
		local f = $(esc(func_expr))
		
		# Get the module path and function name
		local function_key = create_function_key(f)
		
		@debug "Importing remote function $($(QuoteNode(func_expr)))" function_key
		
		$(remote_func_sym)(args...) = 
			RPCClient.call_remote(function_key, args...)
	end
end

end # module RPCClient 