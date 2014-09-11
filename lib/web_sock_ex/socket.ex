defmodule WebSockEx.Socket do
	require Logger

	def write response, socket do
		Logger.debug "Sending: #{inspect response}"
		:gen_tcp.send socket, response
	end
end
