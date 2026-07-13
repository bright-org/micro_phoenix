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
  @response_built 0xE7101109
  @send_rest 0xE710110A
  @send_unexpected 0xE710110B
  @client_done_send_ok 0xE7101110
  @client_done_send_partial_ok 0xE7101111
  @client_done_send_error 0xE7101112
  @client_done_send_unexpected 0xE7101113
  @parse_start 0xE7101120
  @parse_ok 0xE7101121
  @parse_exception 0xE710112F
  @route_start 0xE7101130
  @route_ok 0xE7101131
  @build_start 0xE7101140
  @build_ok 0xE7101141
  @build_exception 0xE710114F
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
      case :gen_tcp.listen(@port, [
             :binary,
             {:active, false},
             {:reuseaddr, true},
             {:packet, :raw} | @listen_options
           ]) do
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

          case response_for(data) do
            {:ok, response} ->
              mark(@send_start)
              send_status = send_response(socket, response)
              mark_client_done(send_status)

            :error ->
              :ok
          end

          close_socket(socket, false)

        {:error, _reason} ->
          mark(@recv_error)
          close_socket(socket, false)
      end
    rescue
      _ ->
        mark(@client_exception)
        close_socket(socket, false)
    catch
      _, _ ->
        mark(@client_exception)
        close_socket(socket, false)
    end
  end

  defp route(request) do
    case MicroPhoenix.Registry.fetch_router() do
      {:ok, route_fn} when is_function(route_fn, 1) ->
        route_fn.(request)

      {:ok, {module, function}} ->
        apply(module, function, [request])

      :error ->
        {:error, 404}
    end
  end

  defp response_for(data) do
    case parse_request(data) do
      {:ok, request} ->
        case route_request(request) do
          {:ok, routed} ->
            build_response(routed)

          :error ->
            :error
        end

      :error ->
        :error
    end
  end

  defp parse_request(data) do
    try do
      mark(@parse_start)
      request = MicroPhoenix.Request.parse(data)
      mark(@parse_ok)
      {:ok, request}
    rescue
      _ ->
        mark(@parse_exception)
        :error
    catch
      _, _ ->
        mark(@parse_exception)
        :error
    end
  end

  defp route_request(request) do
    try do
      mark(@route_start)
      routed = route(request)
      mark(@route_ok)
      {:ok, routed}
    rescue
      _ ->
        # Preserve the last router/controller marker; otherwise this catch-all
        # hides the exact route stage that raised on bare-metal AtomVM.
        :error
    catch
      _, _ ->
        # Preserve the last router/controller marker; otherwise this catch-all
        # hides the exact route stage that raised on bare-metal AtomVM.
        :error
    end
  end

  defp build_response(routed) do
    try do
      mark(@build_start)
      response = MicroPhoenix.Response.build(routed)
      mark(@build_ok)
      mark(@response_built)
      {:ok, response}
    rescue
      _ ->
        mark(@build_exception)
        :error
    catch
      _, _ ->
        mark(@build_exception)
        :error
    end
  end

  defp send_response(socket, response) do
    case :gen_tcp.send(socket, response) do
      :ok ->
        mark(@send_ok)
        :ok

      {:ok, rest} when is_binary(rest) ->
        mark(@send_rest)

        case send_response(socket, rest) do
          :ok -> :partial_ok
          other -> other
        end

      {:error, _reason} ->
        mark(@send_error)
        :error

      _other ->
        mark(@send_unexpected)
        :unexpected
    end
  end

  defp mark_client_done(:ok), do: mark(@client_done_send_ok)
  defp mark_client_done(:partial_ok), do: mark(@client_done_send_partial_ok)
  defp mark_client_done(:error), do: mark(@client_done_send_error)
  defp mark_client_done(:unexpected), do: mark(@client_done_send_unexpected)

  defp close_socket(socket, mark_success) do
    case :gen_tcp.close(socket) do
      :ok ->
        if mark_success do
          mark(@close_ok)
        end

      {:error, _reason} ->
        mark(@close_error)
    end
  end

  defp mark(code) do
    try do
      apply(:fpga_net, :mark, [code])
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
