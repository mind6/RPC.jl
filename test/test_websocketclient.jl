using HTTP.WebSockets, Dates, Serialization

struct CustomData
	timestamp::DateTime
end

WebSockets.open("ws://127.0.0.1:8081") do ws
	# Create a CustomData object
	data = CustomData(DateTime(2023, 1, 1, 12, 0, 0))
	# data = "Hello"

	# Serialize the data into a Vector{UInt8} buffer
	buffer = Vector{UInt8}()
	io = IOBuffer(buffer, write=true)
	Serialization.serialize(io, data)
	serialized_data = take!(io)
	
	# Send the serialized buffer over WebSocket
	send(ws, serialized_data)
	
	# Receive response
	s = receive(ws)
	data2 = deserialize(IOBuffer(s))
	println(data2)
	@assert data == data2

end;
