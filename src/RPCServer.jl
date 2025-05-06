module RPCServer
import ..RPC: send_serialized, deserialize, WebSockets, FunctionName, create_function_key, WrappedError, ResultOrException, Result

export start_server, stop_server, @rpc_export

# Dictionary to store registered functions
const function_registry = Dict{FunctionName, Function}()
server_task = nothing
server = nothing

"""
Macro to register a function with the RPC server
"""
macro rpc_export(func_expr)
	return quote
		# Evaluate the function expression in the caller's module
		local f = $(esc(func_expr))
		
		# Get the function name for display - could be a symbol or an expression
		local display_name = $(QuoteNode(func_expr))
		
		@debug "Registering function" display_name
		
		# Create the FunctionName from the function's module path and name
		local function_key = create_function_key(f)
		
		@debug "Function key: $function_key"
		function_registry[function_key] = f
	end
end

"""
Starts the RPC server on the specified host and port
"""
function start_server(host="127.0.0.1", port=8081)
	global server_task, server
	
	if server_task !== nothing
		@info "RPC server is already running"
		return server
	end
	
	@debug "Starting RPC server on $(host):$(port)"
	server = WebSockets.listen!(host, port) do ws
		@debug "New client connection established"
		for msg in ws
			data::Union{Nothing, Tuple} = nothing
			try
				@debug "Received request from client" 
				# Deserialize the message directly
				data = deserialize(IOBuffer(msg))
				
				if !(data isa Tuple) || length(data) < 2
					@debug "Invalid message format received"
					error_msg = "Invalid message format. Expected (id, function_name, args...) but got $(data)"
					error_response = (0, WrappedError(error_msg, ArgumentError(error_msg), backtrace()))
					send_serialized(ws, error_response)
					continue
				end
				
				id = data[1]
				func_name = data[2]
				args = data[3:end]
				
				@debug "Processing request" id func_name args
				
				if !(func_name isa FunctionName)
					@debug "Function name is not a valid FunctionName" func_name
					error_msg = "Function name must be a Pair{Tuple, Symbol}"
					error_response = (id, WrappedError(error_msg, ArgumentError(error_msg), backtrace()))
					send_serialized(ws, error_response)
					continue
				end
				
				if !haskey(function_registry, func_name)
					@debug "Function not found in registry" func_name
					error_msg = "Function $(func_name) not registered"
					error_response = (id, WrappedError(error_msg, ArgumentError(error_msg), backtrace()))
					send_serialized(ws, error_response)
					continue
				end
				
				# Call the function with the provided arguments
				@debug "Executing function" func_name args
				result = nothing
				try
					result = function_registry[func_name](args...)
					@debug "Function executed successfully" func_name result
					
					# Send the result back to the client with the request ID
					response = (id, Result(result))
					@debug "Sending response to client" id
					send_serialized(ws, response)
				catch e
					@debug "Error in function execution" exception=e catch_backtrace()
					error_msg = "Error executing function $(func_name)"
					error_response = (id, WrappedError(error_msg, e, catch_backtrace()))
					send_serialized(ws, error_response)
				end
			catch e
				@debug "Error processing request" exception=e catch_backtrace()
				# Try to extract the ID if possible
				id = try
					data[1]
				catch
					0  # Default ID if we couldn't extract it
				end
				
				# Send error back to client with ID if available
				error_msg = "Error processing RPC request"
				error_response = (id, WrappedError(error_msg, e, catch_backtrace()))
				send_serialized(ws, error_response)
			end
		end
		@debug "Client connection closed"
	end
	
	server_task = @async begin
		@info "RPC server started on $(host):$(port)"
		wait(server)
	end
	
	return server
end

"""
Helper function to serialize and send an object over WebSocket
"""
# function send_serialized(ws, obj)
# 	@debug "Serializing and sending data"
# 	buffer = Vector{UInt8}()
# 	io = IOBuffer(buffer, write=true)
# 	Serialization.serialize(io, obj)
# 	send(ws, take!(io))
# end

"""
Stops the RPC server
"""
function stop_server()
	global server_task, server
	
	if server === nothing
		@info "RPC server is not running"
		return
	end
	
	@debug "Stopping RPC server"
	close(server)
	server = nothing
	server_task = nothing
	@info "RPC server stopped"
end

end # module RPCServer 