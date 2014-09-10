defmodule WebSockEx.Client do
  require Logger

  @address_port_pattern ~r/(?<address>.*):(?<port>.*)/

  def connect host, path \\ "/" do
    [[address, port]] = Regex.scan @address_port_pattern, host, [capture: :all_names] # TODO real path parsing...
    ###
    ip = {127,0,0,1} # TODO I hate life.
    ###
    case :gen_tcp.connect(ip, String.to_integer(port), []) do
      {:ok, socket} ->
        Logger.debug "Connected to #{address}:#{port}"
        send_handshake socket, {address, port, path}
      {:error, reason} ->
        Logger.debug "Connection could not be established."
    end
  end

  defp send_handshake socket, connection_info do
    handshake = make_handshake connection_info
    :gen_tcp.send(socket, handshake)
    Logger.debug "Handshake sent: \n" <> handshake
  end

  defp make_handshake {address, port, path} do
    "GET #{path} HTTP/1.1\r\n" <>
    "Host: #{address <> ":" <> port}\r\n" <>
    "Upgrade: websocket\r\n" <>
    "Connection: Upgrade\r\n" <>
    "Sec-WebSocket-Version: 13\r\n" <>
    "Sec-WebSocket-Key: #{make_secret_key}\r\n\r\n"
  end

  defp make_secret_key do
    :crypto.rand_bytes(16) |>
      :base64.encode
  end
end
