defmodule MicroPhoenix do
  @port 8080

  def start do
    {:ok, sock} = listen_socket()

    IO.puts("AtomVM HTTP Server listening on http://localhost:#{@port}/")
    accept_loop(sock)
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

  defp listen_socket do
    with {:ok, socket} <- :socket.open(:inet, :stream, :tcp),
         :ok <- :socket.setopt(socket, :socket, :reuseaddr, true),
         :ok <- :socket.bind(socket, %{family: :inet, port: @port, addr: :any}),
         :ok <- :socket.listen(socket) do
      {:ok, socket}
    end
  end
end
