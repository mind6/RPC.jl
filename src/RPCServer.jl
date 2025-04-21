module RPCServer
import ..RPC: send_serialized

export start_server, stop_server, @rpc_export
using HTTP.WebSockets, Serialization

# Dictionary to store registered functions
FunctionName = Pair{<:Tuple, Symbol}
const function_registry = Dict{FunctionName, Function}()
server_task = nothing
server = nothing

"""
Registers a function with the RPC server
"""
function register_function(func::Function, display_name)
	@debug "Registering function $(display_name) with RPC server"
	
	# Create the FunctionName from the function's module path and name
	func_module_path = fullname(typeof(func).name.module)
	func_name = typeof(func).name.name
	function_key = Pair(func_module_path, func_name)
	
	@debug "Function key: $function_key"
	function_registry[function_key] = func
	return nothing
end

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
		
		# Get the actual function name after evaluation
		register_function(f, display_name)
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
					error_response = (0, "Error: Invalid message format. Expected (id, function_name, args...) but got $(data)")
					send_serialized(ws, error_response)
					continue
				end
				
				id = data[1]
				func_name = data[2]
				args = data[3:end]
				
				@debug "Processing request" id func_name args
				
				if !(func_name isa FunctionName)
					@debug "Function name is not a valid FunctionName" func_name
					error_response = (id, "Error: Function name must be a Pair{Tuple, Symbol}")
					send_serialized(ws, error_response)
					continue
				end
				
				if !haskey(function_registry, func_name)
					@debug "Function not found in registry" func_name
					error_response = (id, "Error: Function $(func_name) not registered")
					send_serialized(ws, error_response)
					continue
				end
				
				# Call the function with the provided arguments
				@debug "Executing function" func_name args
				result = function_registry[func_name](args...)
				@debug "Function executed successfully" func_name result
				
				# Send the result back to the client with the request ID
				response = (id, result)
				@debug "Sending response to client" id
				send_serialized(ws, response)
			catch e
				@debug "Error processing request" exception=e catch_backtrace()
				# Try to extract the ID if possible
				id = try
					data[1]
				catch
					0  # Default ID if we couldn't extract it
				end
				
				# Send error back to client with ID if available
				error_response = (id, "Error: $(e)")
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
function send_serialized(ws, obj)
	@debug "Serializing and sending data"
	buffer = Vector{UInt8}()
	io = IOBuffer(buffer, write=true)
	Serialization.serialize(io, obj)
	send(ws, take!(io))
end

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