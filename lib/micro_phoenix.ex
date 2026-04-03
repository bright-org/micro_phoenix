defmodule MicroPhoenix do
  @port 8080

  def start do
    {:ok, sock} =
      :gen_tcp.listen(@port, [:binary, {:active, false}, {:reuseaddr, true}, {:packet, :raw}])

    IO.puts("AtomVM HTTP Server listening on http://localhost:#{@port}/")
    accept_loop(sock)
  end

  defp accept_loop(listen_sock) do
    case :gen_tcp.accept(listen_sock) do
      {:ok, client} ->
        spawn(fn -> handle_client(client) end)
        accept_loop(listen_sock)

      {:error, _reason} ->
        accept_loop(listen_sock)
    end
  end

  defp handle_client(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        response =
          data
          |> MicroPhoenix.Request.parse()
          |> MicroScaffoldExampleWeb.Router.route()
          |> MicroPhoenix.Response.build()

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end
end
