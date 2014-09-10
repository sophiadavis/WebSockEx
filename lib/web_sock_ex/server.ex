defmodule WebSockEx.Server do
	require Logger

	@ws_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	@sec_key_pattern ~r/Sec-WebSocket-Key: (?<key>.*)($|\r\n)/r

	def accept port do
		{:ok, socket} = :gen_tcp.listen(port,
											[:binary, packet: 0, active: false, reuseaddr: true])
		Logger.debug "Listening on port #{port}"
		loop_acceptor socket
	end

	defp loop_acceptor socket do
		{:ok, client} = :gen_tcp.accept(socket)
		serve client # TODO -- Task.Supervisor.start_child(servee...)
		loop_acceptor socket
	end

	defp serve socket do
		{:ok, data} = :gen_tcp.recv(socket, 0) # 0 -- return all available bytes
		Logger.debug "Client connected."
		String.strip(data) |>
			handle_ws_connection |>
			write socket
	end

	defp parse_and_make_response handshake do
		[sec_key] = Regex.run @sec_key_pattern, handshake, [capture: :all_names]
		data = sec_key <> @ws_guid
		:crypto.hash(:sha, data) |>
			:base64.encode |>
			make_response_handshake
	end

	defp handle_ws_connection request do # TODO return tuples, so client socket can be closed if needed
		cond do
			String.contains? request, "Upgrade:" -> parse_and_make_response request
			true ->
				Logger.debug "Non-ws request received."
				"HTTP/1.1 501 Not implemented\r\n\r\n"
		end
	end

	defp make_response_handshake response_key do
		"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{response_key}\r\n\r\n"
	end

	defp write response, socket do
		Logger.debug "\nResponse: \n" <> response
		:gen_tcp.send(socket, response)
	end
end
