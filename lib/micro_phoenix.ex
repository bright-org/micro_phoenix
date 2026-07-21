defmodule MicroPhoenix do
  @port 8080
  @server_name MicroPhoenix.Server

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
      nil ->
        start_server_process()

      pid ->
        {:ok, pid}
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

    with true <- Process.register(self(), @server_name),
         {:ok, socket} <- listen_socket() do
      send(parent, {:server_started, self()})
      IO.puts("AtomVM HTTP Server listening on http://localhost:#{@port}/")
      accept_loop(socket)
    end
  end

  defp accept_loop(listen_sock) do
    case :socket.accept(listen_sock) do
      {:ok, client} ->
        spawn(fn -> handle_client(client) end)
        accept_loop(listen_sock)

      {:error, _reason} ->
        accept_loop(listen_sock)
    end
  end

  defp handle_client(socket) do
    case :socket.recv(socket, 0) do
      {:ok, data} ->
        route_fn = MicroPhoenix.Registry.get_router()

        response =
          data
          |> MicroPhoenix.Request.parse()
          |> route_fn.()
          |> MicroPhoenix.Response.build()

        :ok = :socket.send(socket, response)
        :ok = :socket.close(socket)

      {:error, _} ->
        :ok = :socket.close(socket)
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
end
