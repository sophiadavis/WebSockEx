defmodule WebSockEx.Frame do
	require Logger
	use Bitwise
	'''
	Frame Structure:
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
	@no_mask <<0::size(1)>>
	@mask 	 <<1::size(1)>>

	## fin bit
	@final 		<<1::size(1)>>
	@fragment <<0::size(1)>>

	## opcode definitions
	@continuation <<0::size(1), 0::size(1), 0::size(1), 0::size(1)>> # 0
	@text					<<0::size(1), 0::size(1), 0::size(1), 1::size(1)>> # 1
	@binary				<<0::size(1), 0::size(1), 1::size(1), 0::size(1)>> # 2
	@close				<<1::size(1), 0::size(1), 0::size(1), 0::size(1)>> # 8
	@ping 				<<1::size(1), 0::size(1), 0::size(1), 1::size(1)>> # 9
	@pong					<<1::size(1), 0::size(1), 1::size(1), 0::size(1)>> # A

	def parse_frame <<fin::bits-size(1), rsvs::bits-size(3), rest::bits>> do
		# TODO -- assert that
		<<0::size(3)>> = rsvs

		case fin do
			<<1::size(1)>> ->
				parse_final_frame rest
			<<0::size(1)>> ->
				parse_incomplete_frame rest
		end
	end

	defp parse_incomplete_frame msg do
		:unimplemented
	end

	defp parse_final_frame rest do
		<<opcode::bits-size(4),
			mask::bits-size(1),
			payload_len::bits-size(7),
			rest::bits>> = rest

		cond do
			payload_len == 126 ->
				<<payload_len::bits-size(16), payload::bits>> = rest
			payload_len == 127 ->
				<<payload_len::bits-size(64), payload::bits>> = rest
			true -> payload = rest
		end
		{:ok, :final, parse_mask(mask), parse_opcode(opcode), translate_payload(payload)}
	end

	defp parse_mask(@no_mask), do: :unmasked
	defp parse_mask(@mask), do: :masked

	defp parse_opcode(@continuation), do: :cont
	defp parse_opcode(@text), do: :text
	defp parse_opcode(@binary), do: :binary
	defp parse_opcode(@close), do: :close
	defp parse_opcode(@ping), do: :ping
	defp parse_opcode(@pong), do: :pong

	def translate_payload <<masking_key::bits-size(32), payload::bits>> do
	'''
		transformed-octet-i = original-octet-i XOR masking-key-octet-(i MOD 4)
	'''
		translate_payload payload, masking_key, 0, ""
	end

	defp translate_payload <<>>, _, _, decoded do
		decoded
	end

	defp translate_payload payload, masking_key, i, decoded do
		<<m>> = binary_part payload, 0, 1
		<<n>> = binary_part masking_key, rem(i, 4), 1
		translate_payload binary_part(payload, 1, byte_size(payload) - 1),
					masking_key,
					i + 1,
					decoded <> <<bxor(m,n)>>
	end

	def format_server_frame payload, :text do
		# TODO accurate payload lengths...
		<<@final::bits, 0::size(3), @text::bits,
			@no_mask::bits, byte_size(payload)::size(7), payload::binary>>
	end

	def format_server_frame payload, :close do
		# TODO accurate payload lengths...
		<<@final::bits, 0::size(3), @close::bits,
			@no_mask::bits, byte_size(payload)::size(7), payload::binary>>
	end

	def format_client_frame masking_key, payload, opcode do
		# TODO accurate payload lengths...
		IO.inspect payload
		IO.inspect masking_key
		<<@final::bits, 0::size(3), opcode::bits, @mask::bits,
			byte_size(payload)::size(7), masking_key::binary, payload::binary>>
	end
end
