defmodule WebSockEx.Client do
  require Logger

  @url_pattern ~r"((?<protocol>\w+)://)?(?<address>.*):(?<port>\d+)(?<path>.*)"
  @http_status_pattern ~r"1.1 (?<status>\d{3})"
  @key_hash_pattern ~r"Sec-WebSocket-Accept: (?<status>.*)(\r\n|$)"

  def connect url do
    {:ok, _protocol, address, port, path} = parse_url url
    Logger.debug "Connected to #{address}:#{port}"
    case :gen_tcp.connect(String.to_char_list(address), String.to_integer(port), [{:active, false}]) do # :active, once????????????
      {:ok, socket} ->
        Logger.debug "Connected to #{address}:#{port}"
        nonce = make_nonce
        send_handshake socket, {address, port, path}, nonce
        establish_connection socket, nonce
        {:ok, socket}
      {:error, reason} ->
        Logger.info "Connection could not be established: #{inspect reason}"
        {:error, reason}
    end
  end

  defp parse_url url do
    url_map = Regex.named_captures @url_pattern, url
    IO.inspect url_map
    [{"address", address}, {"path", path}, {"port", port}, {"protocol", protocol}] = Map.to_list url_map
    {:ok, protocol, address, port, path}
  end

  def send_utf payload, socket do
    masking_key = make_masking_key
    IO.inspect masking_key
    masked_payload = WebSockEx.Frame.translate_payload masking_key <> <<payload::binary>>
    packet = WebSockEx.Frame.format_client_frame masking_key, masked_payload, 1
    :gen_tcp.send(socket, packet)
    Logger.debug "Sent packet: #{inspect packet}"
    {:ok, :sent}
  end

  defp establish_connection socket, nonce do
    {:ok, response_handshake} = :gen_tcp.recv(socket, 0)
    Logger.debug "Got response handshake: #{inspect response_handshake}"
    verify_response_handshake List.to_string(response_handshake), nonce
    Logger.debug "Response handshake verified."
  end

  defp verify_response_handshake response_handshake, nonce do
    # I REALLY WANT TO TRY EXCEPT
    # if any of these don't occur (except maybe the status, the connection should fail)
    # maybe just check for true from all of them?
    check_http_status response_handshake
    true = check_for_upgrade response_handshake
    check_key_hash response_handshake, nonce
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

  defp make_masking_key do
    :crypto.rand_bytes(4)
  end
end
