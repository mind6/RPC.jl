module RPC

#=
#TODO: julia serialization is very slow for arrays with missing values, and probably for other complex types as well. It currently takes 5 seconds each way for a 240MB TradeRunSummary object. *ALL* of the bottleneck is in serialization/deserialization. But it's nearly instant for simple arrays of native types. If we want to speed this up we need to use a custom serialization format that skips around the chokepoints of the current implementation.
=#
using Serialization, HTTP.WebSockets

### Function identification ###
FunctionName = Pair{<:Tuple, Symbol}

"""
Creates a function key from a function object.
Used by both server and client to consistently identify functions.
"""
function create_function_key(func::Function)
	func_module_path = fullname(typeof(func).name.module)
	func_name = typeof(func).name.name
	return Pair(func_module_path, func_name)
end

### Serialization ###
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

### Exceptions ###
struct Result
	value::Any
end

struct WrappedError <: Exception
  msg::String
  cause::Exception
  backtrace::Vector{<:Union{Ptr{Nothing}, Base.InterpreterIP}}
end

"""
Prints a WrappedError, showing the original error message, the cause, and the original stacktrace.

NOTE: the override of Base.showerror seems to not be in effect when code is executed from VSCode during startup. From the command line, or from the REPL, or with a second code execution from VSCode, it is effective. Some kind of world age issue?
"""
function Base.showerror(io::IO, we::WrappedError)
  println(io, we.msg)
  println(io, "Caused by: ")
  showerror(io, we.cause)
  println(io, "\nOriginal stacktrace:")
  Base.show_backtrace(io, we.backtrace)
end

# Use a Union type to handle both results and exceptions
const ResultOrException = Union{Result, WrappedError}


### RPC Server and Client ###
include("RPCServer.jl")
include("RPCClient.jl")

using .RPCServer
using .RPCClient
export RPCServer, RPCClient, FunctionName, create_function_key

end # module RPC
