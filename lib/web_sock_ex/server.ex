defmodule WebSockEx.Server do
	require Logger
	use Bitwise

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
		serve client # TODO -- Task.Supervisor.start_child(servee...)
		loop_acceptor socket
	end

	defp serve socket do
		{:ok, packet} = :gen_tcp.recv(socket, 0)
		Logger.debug "Client connected."
		String.strip(packet) |>
			handle_ws_connection |>
			write socket
		receive_frames socket
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

	defp receive_frames socket do
		{:ok, packet} = :gen_tcp.recv(socket, 0)
		Logger.debug "Received message: #{IO.inspect parse_frame packet}"
		receive_frames socket
	end

'''
	0                   1                   2                   3
	0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
	+-+-+-+-+-------+-+-------------+-------------------------------+
	|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
	|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
	|N|V|V|V|       |S|             |   (if payload len==126/127)   |
	| |1|2|3|       |K|             |                               |
	+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
	|     Extended payload length continued, if payload len == 127  |
	+ - - - - - - - - - - - - - - - +-------------------------------+
	|                               |Masking-key, if MASK set to 1  |
	+-------------------------------+-------------------------------+
	| Masking-key (continued)       |          Payload Data         |
	+-------------------------------- - - - - - - - - - - - - - - - +
	:                     Payload Data continued ...                :
	+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
	|                     Payload Data continued ...                |
	+---------------------------------------------------------------+
'''

	defp parse_frame <<fin::bits-size(1), rsvs::bits-size(3), rest::bits>> do

		# TODO -- assert that
		<<0::size(3)>> = rsvs

		case fin do
			<<1::size(1)>> ->
				parse_final_frame rest, []
			<<0::size(1)>> ->
				parse_incomplete_frame rest, []
		end
	end

	defp parse_final_frame msg, current_payload do
		<<opcode::bits-size(4),
			mask::bits-size(1),
			payload_len::bits-size(7),
			rest::bits>> = msg

		# TODO -- assert that
		<<1::size(1)>> = mask

		Logger.debug "Opcode: #{inspect opcode}"
		# TODO deal w opcode, and it's hex??
			# *  %x0 denotes a continuation frame
			# *  %x1 denotes a text frame
			# *  %x2 denotes a binary frame
			# *  %x3-7 are reserved for further non-control frames
			# *  %x8 denotes a connection close
			# *  %x9 denotes a ping
			# *  %xA denotes a pong
			# *  %xB-F are reserved for further control frames

		cond do
			payload_len == 126 ->
				<<payload_len::bits-size(16), rest::bits>> = rest
			payload_len == 127 ->
				<<payload_len::bits-size(64), rest::bits>> = rest
			true -> rest = rest
		end
		unmask rest
	end

	defp parse_incomplete_frame msg, current_payload do
		:unimplemented
	end

	defp unmask <<mask_key::bits-size(32), payload::bits>> do
	'''
  	transformed-octet-i = original-octet-i XOR masking-key-octet-(i MOD 4)
	'''
		unmask payload, mask_key, 0, ""
	end

	defp unmask <<>>, _, _, decoded do
		decoded
	end

	defp unmask payload, mask_key, i, decoded do
		<<m>> = binary_part payload, 0, 1
		<<n>> = binary_part mask_key, rem(i, 4), 1
		unmask binary_part(payload, 1, byte_size(payload) - 1),
					 mask_key,
					 i + 1,
					 decoded <> <<bxor(m,n)::utf8>>
	end

	defp write response, socket do
		Logger.debug "\nResponse: \n" <> response
		:gen_tcp.send(socket, response)
	end

	def make_response_secret nonce do #TODO move to new file
		:crypto.hash(:sha, nonce <> @ws_guid) |>
			Base.encode64
	end
end
