defmodule WebSockEx.Client do
  require Logger

  @address_port_pattern ~r"(?<address>.*):(?<port>.*)"
  @http_status_pattern ~r"1.1 (?<status>\d{3})"
  @key_hash_pattern ~r"Sec-WebSocket-Accept: (?<status>.*)(\r\n|$)"

  def connect host, path \\ "/" do
    [[address, port]] = Regex.scan @address_port_pattern, host, [capture: :all_names] # TODO real path parsing...
    ###
    ip = {127,0,0,1} # TODO I hate life.
    ###
    case :gen_tcp.connect(ip, String.to_integer(port), [{:active, false}]) do
      {:ok, socket} ->
        Logger.debug "Connected to #{address}:#{port}"
        nonce = make_nonce
        send_handshake socket, {address, port, path}, nonce
        handle_connection socket, nonce
      {:error, reason} ->
        Logger.debug "Connection could not be established: " <> reason
    end
  end

  defp handle_connection socket, nonce do
    {:ok, response_handshake} = :gen_tcp.recv(socket, 0)
    Logger.debug "Received response handshake: \n#{IO.inspect response_handshake}"
    verify_response_handshake List.to_string(response_handshake), nonce
    Logger.debug "Response handshake verified."
  end

  defp verify_response_handshake response_handshake, nonce do
    # I REALLY WANT TO TRY EXCEPT
    # if any of these don't occur (except maybe the status, the connection should fail)
    check_http_status response_handshake
    Logger.debug " -- verified: http status code"
    true = check_for_upgrade response_handshake
    Logger.debug " -- verified: upgrade request"
    check_key_hash response_handshake, nonce
    Logger.debug " -- verified: key hash"
    # TODO check Sec-WebSocket-Extensions contains an extension I sent
    :ok
  end

  defp check_http_status response_handshake do
    [http_status] = Regex.run @http_status_pattern, response_handshake, [capture: :all_names]
    # TODO "If the status code received from the server is not 101, the client handles the response per HTTP [RFC2616] procedures."
    {:ok, http_status}
  end

  defp check_for_upgrade response_handshake do
    String.downcase(response_handshake) |>
    String.contains? "connection: upgrade"
  end

  defp check_key_hash response_handshake, nonce do
    [key_hash] = Regex.run @key_hash_pattern, response_handshake, [capture: :all_names]
    correct_hash = WebSockEx.Server.make_response_secret nonce
    correct_hash = key_hash
  end

  defp send_handshake socket, connection_info, nonce do
    handshake = make_handshake connection_info, nonce
    :gen_tcp.send(socket, handshake)
    Logger.debug "Handshake sent: \n" <> handshake
  end

  defp make_handshake {address, port, path}, nonce do
    "GET #{path} HTTP/1.1\r\n" <>
    "Host: #{address <> ":" <> port}\r\n" <>
    "Upgrade: websocket\r\n" <>
    "Connection: Upgrade\r\n" <>
    "Sec-WebSocket-Version: 13\r\n" <>
    "Sec-WebSocket-Key: #{nonce}\r\n\r\n"
  end

  defp make_nonce do
    :crypto.rand_bytes(16) |>
      Base.encode64
  end
end
