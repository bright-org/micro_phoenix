defmodule MicroPhoenix.TransportTest do
  use ExUnit.Case, async: false

  @http_transport Application.compile_env(:micro_phoenix, :http_transport, :socket)
  @root_response "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 18\r\nConnection: close\r\n\r\nHello from AtomVM\n"

  test "only imports the configured server transport" do
    {:ok, {MicroPhoenix, [{:imports, imports}]}} =
      MicroPhoenix
      |> :code.which()
      |> :beam_lib.chunks([:imports])

    imported_transports =
      imports
      |> Enum.map(fn {module, _function, _arity} -> module end)
      |> Enum.filter(&(&1 in [:socket, :gen_tcp]))
      |> MapSet.new()

    assert imported_transports == MapSet.new([@http_transport])
    refute {:gen_tcp, :controlling_process, 2} in imports
  end

  test "serves the root fast path through the configured transport" do
    assert {:ok, socket} =
             :gen_tcp.connect({127, 0, 0, 1}, 5000, [
               :binary,
               {:active, false},
               {:packet, :raw}
             ])

    assert :ok = :gen_tcp.send(socket, "GET / HTTP/1.1\r\nhost: localhost\r\n\r\n")
    assert @root_response == receive_all(socket, "")
  end

  defp receive_all(socket, response) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, data} -> receive_all(socket, response <> data)
      {:error, :closed} -> response
    end
  end
end
