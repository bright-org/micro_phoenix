defmodule Phoenix.WebSocket do
  @moduledoc false
  import Bitwise

  @guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  def serve(socket, request, buffered, socket_module, opts) do
    if function_exported?(socket_module, :connect, 3) do
      do_serve(socket, request, buffered, socket_module, opts)
    else
      reject(socket, 404, "Not Found")
    end
  end

  defp do_serve(socket, request, buffered, socket_module, opts) do
    case handshake(request) do
      {:ok, key, params, headers} ->
        if allowed_origin?(headers, opts) do
          initial_socket = %Phoenix.Socket{
            transport_pid: self(),
            pubsub_server: Keyword.get(opts, :pubsub)
          }

          case socket_module.connect(params, initial_socket, %{}) do
            {:ok, %Phoenix.Socket{} = state} ->
              accept = Phoenix.WebSocket.SHA1.hash(key <> @guid) |> Base.encode64()

              response =
                "HTTP/1.1 101 Switching Protocols\r\n" <>
                  "Upgrade: websocket\r\nConnection: Upgrade\r\n" <>
                  "Sec-WebSocket-Accept: #{accept}\r\n\r\n"

              case send_bytes(socket, response) do
                :ok -> frame_loop(socket, buffered, {socket_module, state, %{}})
                error -> error
              end

            _ ->
              reject(socket, 403, "Forbidden")
          end
        else
          reject(socket, 403, "Forbidden")
        end

      :error ->
        reject(socket, 400, "Bad Request")
    end
  rescue
    e ->
      :erlang.display({:websocket_error, e, __STACKTRACE__})
      :error
  end

  defp handshake(request) do
    [head | _] = Phoenix.Binary.split2(request, "\r\n\r\n")
    [request_line | header_lines] = Phoenix.Binary.split(head, "\r\n")
    headers = Enum.map(header_lines, &parse_header/1)

    with ["GET", target, "HTTP/1.1"] <- Phoenix.Binary.split(request_line, " "),
         "websocket" <- Phoenix.Binary.downcase_ascii(header(headers, "upgrade")),
         true <- token?(header(headers, "connection"), "upgrade"),
         "13" <- header(headers, "sec-websocket-version"),
         key when is_binary(key) <- header(headers, "sec-websocket-key"),
         {:ok, decoded} <- Base.decode64(key),
         true <- byte_size(decoded) == 16 and Base.encode64(decoded) == key,
         host when is_binary(host) <- header(headers, "host") do
      [_path | query_parts] = Phoenix.Binary.split2(target, "?")

      query =
        case query_parts do
          [part] -> part
          [] -> ""
        end

      params =
        Enum.reduce(AtomVM.URI.query_decoder(query), %{}, fn {k, v}, acc -> Map.put(acc, k, v) end)

      {:ok, key, params, headers}
    else
      _ -> :error
    end
  end

  defp parse_header(line) do
    case Phoenix.Binary.split2(line, ":") do
      [key, value] -> {Phoenix.Binary.downcase_ascii(key), trim(value)}
      _ -> {"", ""}
    end
  end

  defp header(headers, key) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp token?(value, token) when is_binary(value) do
    Enum.any?(Phoenix.Binary.split(value, ","), fn part ->
      Phoenix.Binary.downcase_ascii(trim(part)) == token
    end)
  end

  defp token?(_, _), do: false

  defp allowed_origin?(headers, opts) do
    case Keyword.get(opts, :check_origin) do
      nil -> true
      false -> true
      allowed when is_list(allowed) -> header(headers, "origin") in allowed
    end
  end

  defp trim(<<c, rest::binary>>) when c in [32, 9], do: trim(rest)
  defp trim(value), do: trim_right(value)
  defp trim_right(<<>>), do: <<>>

  defp trim_right(value) do
    size = byte_size(value)
    <<prefix::binary-size(size - 1), last>> = value
    if last in [32, 9], do: trim_right(prefix), else: value
  end

  defp reject(socket, status, reason) do
    send_bytes(
      socket,
      "HTTP/1.1 #{status} #{reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )
  end

  @max_frame 1_000_000

  defp frame_loop(socket, buffered, state) do
    with {:ok, data} <- ensure_bytes(socket, buffered, 2) do
      <<fin::1, rsv::3, opcode::4, masked::1, len::7, rest::binary>> = data

      cond do
        fin != 1 or rsv != 0 or masked != 1 ->
          close_frame(socket, 1002)

        opcode in [8, 9, 10] and len >= 126 ->
          close_frame(socket, 1002)

        true ->
          case payload_length(socket, rest, len) do
            {:error, code} when is_integer(code) ->
              close_frame(socket, code)

            {:ok, length, rest} ->
              with {:ok, data} <- ensure_bytes(socket, rest, length + 4) do
                <<mask::binary-size(4), payload::binary-size(length), tail::binary>> = data
                decoded = unmask(payload, mask)

                case opcode do
                  8 ->
                    send_frame(socket, 8, decoded)

                  9 ->
                    case send_frame(socket, 10, decoded) do
                      :ok -> frame_loop(socket, tail, state)
                      error -> error
                    end

                  10 ->
                    frame_loop(socket, tail, state)

                  1 ->
                    case Phoenix.Socket.Transport.handle(decoded, state) do
                      {:reply, body, next_state} ->
                        case send_frame(socket, 1, body) do
                          :ok -> frame_loop(socket, tail, next_state)
                          error -> error
                        end

                      {:noreply, next_state} ->
                        frame_loop(socket, tail, next_state)

                      {:error, _} ->
                        close_frame(socket, 1007)
                    end

                  _ ->
                    close_frame(socket, 1003)
                end
              end

            error ->
              error
          end
      end
    end
  end

  defp payload_length(_socket, rest, len) when len < 126, do: {:ok, len, rest}

  defp payload_length(socket, rest, 126) do
    with {:ok, <<len::16, tail::binary>>} <- ensure_bytes(socket, rest, 2) do
      cond do
        len < 126 -> {:error, 1002}
        len > @max_frame -> {:error, 1009}
        true -> {:ok, len, tail}
      end
    end
  end

  defp payload_length(socket, rest, 127) do
    with {:ok, <<len::64, tail::binary>>} <- ensure_bytes(socket, rest, 8) do
      cond do
        len < 65_536 -> {:error, 1002}
        len > @max_frame -> {:error, 1009}
        true -> {:ok, len, tail}
      end
    end
  end

  defp ensure_bytes(_socket, data, count) when byte_size(data) >= count, do: {:ok, data}

  defp ensure_bytes(socket, data, count) do
    case :socket.recv(socket, 0, 100) do
      {:ok, chunk} when byte_size(chunk) > 0 ->
        ensure_bytes(socket, data <> chunk, count)

      {:error, :timeout} ->
        receive do
          {:channel_push, join_ref, topic, event, payload} ->
            body =
              :json.encode([join_ref, :null, topic, event, payload]) |> :erlang.iolist_to_binary()

            case send_frame(socket, 1, body) do
              :ok -> ensure_bytes(socket, data, count)
              error -> error
            end

          %Phoenix.Socket.Broadcast{topic: topic, event: event, payload: payload} ->
            body =
              :json.encode([:null, :null, topic, event, payload]) |> :erlang.iolist_to_binary()

            case send_frame(socket, 1, body) do
              :ok -> ensure_bytes(socket, data, count)
              error -> error
            end
        after
          0 -> ensure_bytes(socket, data, count)
        end

      error ->
        error
    end
  end

  defp unmask(data, key), do: unmask(data, key, key, <<>>)
  defp unmask(<<>>, _key, _original, result), do: result
  defp unmask(data, <<>>, original, result), do: unmask(data, original, original, result)

  defp unmask(<<byte, rest::binary>>, <<mask, next::binary>>, original, result) do
    unmask(rest, next, original, <<result::binary, bxor(byte, mask)>>)
  end

  defp close_frame(socket, code), do: send_bytes(socket, <<0x88, 2, code::16>>)

  defp send_frame(socket, opcode, payload) do
    length = byte_size(payload)

    cond do
      length < 126 ->
        send_bytes(socket, <<1::1, 0::3, opcode::4, 0::1, length::7, payload::binary>>)

      length < 65_536 ->
        send_bytes(socket, <<1::1, 0::3, opcode::4, 0::1, 126::7, length::16, payload::binary>>)

      true ->
        send_bytes(socket, <<1::1, 0::3, opcode::4, 0::1, 127::7, length::64, payload::binary>>)
    end
  end

  defp send_bytes(socket, data) do
    case :socket.send(socket, data) do
      :ok -> :ok
      {:ok, <<>>} -> :ok
      {:ok, rest} -> send_bytes(socket, rest)
      error -> error
    end
  end
end
