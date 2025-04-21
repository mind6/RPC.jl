module RPC

"""
Helper function to serialize and send an object over WebSocket
"""
function send_serialized(ws, obj)
	@debug "Core: Serializing and sending data"
	buffer = Vector{UInt8}()
	io = IOBuffer(buffer, write=true)
	Serialization.serialize(io, obj)
	send(ws, take!(io))
end

include("RPCServer.jl")
include("RPCClient.jl")

using .RPCServer
using .RPCClient
export RPCServer, RPCClient

end # module RPC
