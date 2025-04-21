using HTTP.WebSockets
server = WebSockets.listen!("127.0.0.1", 8081) do ws
	for msg in ws
		 send(ws, msg)
	end
end