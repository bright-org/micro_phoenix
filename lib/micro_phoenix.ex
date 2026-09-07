defmodule MicroPhoenix do
  @port Application.compile_env(:micro_phoenix, :port, 8080)
  @server_name MicroPhoenix.Server
  @listen_start 0xE7101101
  @listen_ok 0xE7101102
  @accept_ok 0xE7101103
  @recv_wait 0xE7101104
  @gen_tcp_socket_recv_return 0xE71011AC
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
  @fast_response_index 0xE7101114
  @fast_response_index_html 0xE7101115
  @fast_response_miss 0xE7101116
  @parse_start 0xE7101120
  @parse_ok 0xE7101121
  @parse_exception 0xE710112F
  @route_start 0xE7101130
  @route_ok 0xE7101131
  @route_fetch_router_enter 0xE7101137
  @route_fetch_router_ok_fn 0xE7101138
  @route_fetch_router_ok_mfa 0xE7101139
  @route_call_enter 0xE710113A
  @route_call_returned 0xE710113B
  @route_fetch_router_error 0xE710113C
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
  @index_fast_response "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 18\r\nConnection: close\r\n\r\nHello from AtomVM\n"

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start() do
    case run_server() do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def start_link() do
    case Process.whereis(@server_name) do
      nil -> start_server_process()
      pid -> {:ok, pid}
    end
  end

  defp start_server_process() do
    parent = self()

    pid =
      spawn_link(fn ->
        case run_server(parent) do
          {:ok, _pid} -> :ok
          {:error, reason} -> exit(reason)
        end
      end)

    receive do
      {:server_started, ^pid} -> {:ok, pid}
    after
      1_000 -> {:error, :timeout}
    end
  end

  defp run_server(parent \\ self()) do
    MicroPhoenix.Registry.ensure_started()
    mark(@listen_start)

    try do
      with true <- Process.register(self(), @server_name),
           {:ok, socket} <- listen_socket() do
        mark(@listen_ok)
        send(parent, {:server_started, self()})
        IO.puts("AtomVM HTTP Server listening on http://localhost:#{@port}/")
        accept_loop(socket)
      else
        false ->
          mark(@listen_failed)
          {:error, :already_started}

        {:error, reason} ->
          mark(@listen_failed)
          {:error, reason}
      end
    rescue
      error ->
        mark(@listen_exception)
        {:error, error}
    catch
      kind, reason ->
        mark(@listen_exception)
        {:error, {kind, reason}}
    end
  end

  defp accept_loop(listen_sock) do
    case :socket.accept(listen_sock) do
      {:ok, client} ->
        mark(@accept_ok)
        spawn(fn -> handle_client(client) end)
        accept_loop(listen_sock)

      {:error, _reason} ->
        mark(@accept_error)
        accept_loop(listen_sock)
    end
  end

  defp handle_client(socket) do
    try do
      mark(@recv_wait)

      case :socket.recv(socket, 0) do
        {:ok, data} ->
          # Keep the established app-side receive boundary marker while the
          # transport moves from :gen_tcp to direct :socket calls.
          mark(@gen_tcp_socket_recv_return)
          mark(@recv_ok)

          case fast_response_for(data) do
            {:ok, response} ->
              send_and_mark(socket, response)

            :error ->
              case response_for(data) do
                {:ok, response} -> send_and_mark(socket, response)
                :error -> :ok
              end
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

  defp send_and_mark(socket, response) do
    mark(@send_start)
    socket |> send_response(response) |> mark_client_done()
  end

  defp fast_response_for(<<"GET / HTTP/1.", _rest::binary>>) do
    mark(@fast_response_index)
    {:ok, @index_fast_response}
  end

  defp fast_response_for(<<"GET /index.html HTTP/1.", _rest::binary>>) do
    mark(@fast_response_index_html)
    {:ok, @index_fast_response}
  end

  defp fast_response_for(_data) do
    mark(@fast_response_miss)
    :error
  end

  defp response_for(data) do
    case parse_request(data) do
      {:ok, request} ->
        case route_request(request) do
          {:ok, routed} -> build_response(routed)
          :error -> :error
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
      _ -> :error
    catch
      _, _ -> :error
    end
  end

  defp route(request) do
    mark(@route_fetch_router_enter)

    case MicroPhoenix.Registry.fetch_router() do
      {:ok, route_fn} when is_function(route_fn, 1) ->
        mark(@route_fetch_router_ok_fn)
        mark(@route_call_enter)
        routed = route_fn.(request)
        mark(@route_call_returned)
        routed

      {:ok, {module, function}} ->
        mark(@route_fetch_router_ok_mfa)
        mark(@route_call_enter)
        routed = apply(module, function, [request])
        mark(@route_call_returned)
        routed

      :error ->
        mark(@route_fetch_router_error)
        {:error, 404}
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
    case :socket.send(socket, response) do
      :ok ->
        mark(@send_ok)
        :ok

      {:ok, <<>>} ->
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
    case :socket.close(socket) do
      :ok ->
        if mark_success do
          mark(@close_ok)
        end

      {:error, _reason} ->
        mark(@close_error)
    end
  end

  defp listen_socket() do
    with {:ok, socket} <- :socket.open(:inet, :stream, :tcp),
         :ok <- :socket.setopt(socket, {:socket, :reuseaddr}, true),
         :ok <- :socket.bind(socket, %{family: :inet, port: @port, addr: :any}),
         :ok <- :socket.listen(socket) do
      {:ok, socket}
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
end
