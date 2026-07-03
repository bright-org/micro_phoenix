defmodule MicroPhoenix do
  @port Application.compile_env(:micro_phoenix, :port, 8080)
  @listen_options Application.compile_env(:micro_phoenix, :listen_options, [])
  @listen_start 0xE7101101
  @listen_ok 0xE7101102
  @accept_ok 0xE7101103
  @recv_wait 0xE7101104
  @recv_ok 0xE7101105
  @send_start 0xE7101106
  @send_ok 0xE7101107
  @close_ok 0xE7101108
  @accept_error 0xE71011E3
  @recv_error 0xE71011E5
  @send_error 0xE71011E7
  @close_error 0xE71011E8
  @listen_failed 0xE71011F0
  @listen_exception 0xE71011F1
  @client_exception 0xE71011F2

  def start do
    mark(@listen_start)

    try do
      case :gen_tcp.listen(@port, [:binary, {:active, false}, {:reuseaddr, true}, {:packet, :raw} | @listen_options]) do
        {:ok, sock} ->
          mark(@listen_ok)
          accept_loop(sock)

        {:error, _reason} ->
          mark(@listen_failed)
          wait_forever()
      end
    catch
      _, _ ->
        mark(@listen_exception)
        wait_forever()
    end
  end

  defp accept_loop(listen_sock) do
    case :gen_tcp.accept(listen_sock) do
      {:ok, client} ->
        mark(@accept_ok)
        handle_client(client)
        accept_loop(listen_sock)

      {:error, _reason} ->
        mark(@accept_error)
        accept_loop(listen_sock)
    end
  end

  defp handle_client(socket) do
    try do
      mark(@recv_wait)

      case :gen_tcp.recv(socket, 0) do
        {:ok, data} ->
          mark(@recv_ok)
          mark(@send_start)

          case :gen_tcp.send(socket, response_for(data)) do
            :ok ->
              mark(@send_ok)

            {:error, _reason} ->
              mark(@send_error)
          end

          close_socket(socket)

        {:error, _reason} ->
          mark(@recv_error)
          close_socket(socket)
      end
    rescue
      _ ->
        mark(@client_exception)
        close_socket(socket)
    catch
      _, _ ->
        mark(@client_exception)
        close_socket(socket)
    end
  end

  defp close_socket(socket) do
    case :gen_tcp.close(socket) do
      :ok ->
        mark(@close_ok)

      {:error, _reason} ->
        mark(@close_error)
    end
  end

  defp response_for(<<"GET /api/status", _rest::binary>>) do
    body = ~s({"status":"ok","vm":"AtomVM","app":"micro_phoenix"})
    response("HTTP/1.1 200 OK", "application/json", body)
  end

  defp response_for(<<"GET / ", _rest::binary>>) do
    body = """
    <!DOCTYPE html>
    <html><body><h1>MicroPhoenix on AtomVM</h1><p>OK</p></body></html>
    """

    response("HTTP/1.1 200 OK", "text/html", body)
  end

  defp response_for(_request) do
    response("HTTP/1.1 404 Not Found", "text/plain", "404 Not Found")
  end

  defp response(status_line, content_type, body) do
    status_line <>
      "\r\nContent-Type: " <>
      content_type <>
      "; charset=utf-8\r\nContent-Length: " <>
      :erlang.integer_to_binary(byte_size(body)) <>
      "\r\nConnection: close\r\n\r\n" <>
      body
  end

  defp mark(code) do
    try do
      :fpga_net.mark(code)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    :ok
  end

  defp wait_forever do
    receive do
    after
      1000 -> wait_forever()
    end
  end
end
