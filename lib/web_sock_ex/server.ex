defmodule WebSockEx.Server do
	require Logger

	@ws_guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	@sec_key_pattern ~r"Sec-WebSocket-Key: (?<key>.*)($|\r\n)"r

	def accept port do
		{:ok, socket} = :gen_tcp.listen(port,
											[:binary, packet: 0, active: false, reuseaddr: true])
		Logger.debug "Listening on port #{port}"
		loop_acceptor socket
	end

	defp loop_acceptor socket do
		{:ok, client} = :gen_tcp.accept(socket)
		Task.Supervisor.start_child(:server_pool, fn -> serve client end)
		loop_acceptor socket
	end

	defp serve socket do
		{:ok, packet} = :gen_tcp.recv(socket, 0)
		Logger.debug "Client connected."
		String.strip(packet) |>
			handle_ws_connection |>
			write socket
		send_and_receive_frames socket
	end

	defp parse_and_make_response handshake do
		[nonce] = Regex.run @sec_key_pattern, handshake, [capture: :all_names]
		nonce |>
			make_response_secret |>
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
		"HTTP/1.1 101 Switching Protocols\r\n" <>
		"Upgrade: websocket\r\n" <>
		"Connection: Upgrade\r\n" <>
		"Sec-WebSocket-Accept: #{response_key}\r\n\r\n"
	end

	defp send_and_receive_frames socket do
		{:ok, packet} = :gen_tcp.recv(socket, 0)
		{:ok, msg} = WebSockEx.Frame.parse_frame packet
		Logger.debug "Received message: #{inspect msg}"
		WebSockEx.Frame.format_server_frame(msg, 1) |>
			write socket
		send_and_receive_frames socket
	end

	defp write response, socket do
		Logger.debug "\nSending response: \n#{inspect response}"
		:gen_tcp.send(socket, response)
	end

	def make_response_secret nonce do #TODO move to new file
		:crypto.hash(:sha, nonce <> @ws_guid) |>
			Base.encode64
	end
end
