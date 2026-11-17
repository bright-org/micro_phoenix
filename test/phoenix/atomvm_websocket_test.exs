defmodule Phoenix.AtomVM.WebSocketTest do
  use ExUnit.Case

  defmodule Router do
    def call(conn, _opts), do: %{conn | status: 404, resp_body: "Not Found"}
  end

  defmodule RoomChannel do
    use Phoenix.Channel

    def join("room:lobby", _params, socket), do: {:ok, socket}

    def handle_in("echo", %{"message" => message}, socket),
      do: {:reply, {:ok, %{"message" => message}}, socket}

    def handle_in("push", payload, socket) do
      :ok = Phoenix.Channel.push(socket, "pushed", payload)
      {:reply, {:ok, %{}}, socket}
    end

    def handle_in("broadcast", payload, socket) do
      :ok = Phoenix.Channel.broadcast_from(socket, "new_msg", payload)
      {:reply, {:ok, %{}}, socket}
    end
  end

  defmodule Socket do
    use Phoenix.Socket
    channel("room:lobby", Phoenix.AtomVM.WebSocketTest.RoomChannel)

    def connect(_params, socket, _connect_info), do: {:ok, socket}
  end

  defmodule NoConnectSocket do
    @moduledoc false
  end

  setup do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, pubsub} = Phoenix.PubSub.start_link(name: :micro_phoenix_channel_pubsub)
    on_exit(fn -> Process.exit(pubsub, :kill) end)

    {:ok, pid} =
      Task.start(fn ->
        Phoenix.AtomVM.run(Router,
          port: port,
          static: [],
          socket: {"/socket/websocket", Socket, pubsub: :micro_phoenix_channel_pubsub}
        )
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    {:ok, socket} = connect(port, 30)
    on_exit(fn -> :gen_tcp.close(socket) end)
    {:ok, socket: socket, pubsub: pubsub, port: port}
  end

  test "upgrades a mounted socket after validating the handshake", %{socket: socket} do
    :ok =
      :gen_tcp.send(
        socket,
        "GET /socket/websocket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
      )

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    assert response =~ "HTTP/1.1 101 Switching Protocols\r\n"
    assert response =~ "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    :ok = :gen_tcp.send(socket, <<0x89, 0x81, 1, 2, 3, 4, 0x71>>)
    assert {:ok, <<0x8A, 1, ?p>>} = :gen_tcp.recv(socket, 3, 1_000)
  end

  test "rejects an unmasked client frame", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _response, _rest} = recv_headers(socket, <<>>)

    :ok = :gen_tcp.send(socket, <<0x89, 1, ?p>>)
    assert {:ok, <<0x88, 2, 1002::16>>} = :gen_tcp.recv(socket, 4, 1_000)
  end

  test "preserves a frame received with the upgrade request", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request() <> <<0x89, 0x81, 1, 2, 3, 4, 0x71>>)
    assert {:ok, response, rest} = recv_headers(socket, <<>>)
    assert response =~ "HTTP/1.1 101 Switching Protocols"

    data =
      if byte_size(rest) < 3 do
        {:ok, chunk} = :gen_tcp.recv(socket, 3 - byte_size(rest), 1_000)
        rest <> chunk
      else
        rest
      end

    assert <<0x8A, 1, ?p>> = data
  end

  test "joins a channel over a masked V2 text frame", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, response, <<>>} = recv_headers(socket, <<>>)
    assert response =~ "HTTP/1.1 101 Switching Protocols"

    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "1",
             "2",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{}}
           ]
  end

  test "replies to an event after joining and rejects an unknown topic", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _, <<>>} = recv_headers(socket, <<>>)

    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, _} = recv_text(socket)

    send_text(socket, ~s(["1","3","room:lobby","echo",{"message":"hello"}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "1",
             "3",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{"message" => "hello"}}
           ]

    send_text(socket, ~s(["4","5","missing","phx_join",{}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "4",
             "5",
             "missing",
             "phx_reply",
             %{"status" => "error", "response" => %{"reason" => "unmatched_topic"}}
           ]
  end

  test "handles extended-length channel frames", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _, <<>>} = recv_headers(socket, <<>>)

    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, _} = recv_text(socket)

    message = String.duplicate("x", 130)
    send_text(socket, Jason.encode!(["1", "3", "room:lobby", "echo", %{"message" => message}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "1",
             "3",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{"message" => message}}
           ]
  end

  test "pushes a channel event to the connected client", %{socket: socket} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _, <<>>} = recv_headers(socket, <<>>)
    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, _} = recv_text(socket)

    send_text(socket, ~s(["1","3","room:lobby","push",{"message":"hello"}]))
    assert {:ok, first} = recv_text(socket)
    assert {:ok, second} = recv_text(socket)

    assert Enum.sort([Jason.decode!(first), Jason.decode!(second)]) ==
             Enum.sort([
               ["1", "3", "room:lobby", "phx_reply", %{"status" => "ok", "response" => %{}}],
               ["1", nil, "room:lobby", "pushed", %{"message" => "hello"}]
             ])
  end

  test "broadcasts to another joined connection and cleans up a closed subscriber", %{
    socket: first,
    pubsub: pubsub,
    port: port
  } do
    {:ok, second} = connect(port, 1)
    on_exit(fn -> :gen_tcp.close(second) end)

    for socket <- [first, second] do
      :ok = :gen_tcp.send(socket, upgrade_request())
      assert {:ok, _, <<>>} = recv_headers(socket, <<>>)
      send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
      assert {:ok, _} = recv_text(socket)
    end

    send_text(first, ~s(["1","3","room:lobby","broadcast",{"message":"hello"}]))
    assert {:ok, reply} = recv_text(first)

    assert Jason.decode!(reply) == [
             "1",
             "3",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{}}
           ]

    assert {:error, :timeout} = :gen_tcp.recv(first, 0, 100)
    assert {:ok, broadcast} = recv_text(second)

    assert Jason.decode!(broadcast) == [
             nil,
             nil,
             "room:lobby",
             "new_msg",
             %{"message" => "hello"}
           ]

    assert {:monitors, monitors} = Process.info(pubsub, :monitors)
    assert length(monitors) == 2
    :ok = :gen_tcp.close(second)

    assert Enum.any?(1..20, fn _ ->
             if match?({:monitors, [_]}, Process.info(pubsub, :monitors)) do
               true
             else
               Process.sleep(10)
               false
             end
           end)

    :ok =
      Phoenix.PubSub.broadcast(
        :micro_phoenix_channel_pubsub,
        "room:lobby",
        %Phoenix.Socket.Broadcast{topic: "room:lobby", event: "probe", payload: %{}}
      )

    assert {:ok, event} = recv_text(first)
    assert Jason.decode!(event) == [nil, nil, "room:lobby", "probe", %{}]
  end

  test "leaves a joined topic and removes its subscription", %{socket: socket, pubsub: pubsub} do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _, <<>>} = recv_headers(socket, <<>>)
    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, _} = recv_text(socket)
    assert {:monitors, [_]} = Process.info(pubsub, :monitors)

    send_text(socket, ~s(["1","3","room:lobby","phx_leave",{}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "1",
             "3",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{}}
           ]

    assert Process.info(pubsub, :monitors) == {:monitors, []}
    send_text(socket, ~s(["1","4","room:lobby","echo",{"message":"stale"}]))
    assert {:ok, stale_reply} = recv_text(socket)

    assert Jason.decode!(stale_reply) == [
             "1",
             "4",
             "room:lobby",
             "phx_reply",
             %{"status" => "error", "response" => %{"reason" => "unmatched_topic"}}
           ]
  end

  test "rejoins after leaving with a new join reference and receives broadcasts", %{
    socket: socket,
    pubsub: pubsub
  } do
    :ok = :gen_tcp.send(socket, upgrade_request())
    assert {:ok, _, <<>>} = recv_headers(socket, <<>>)

    send_text(socket, ~s(["1","2","room:lobby","phx_join",{}]))
    assert {:ok, _} = recv_text(socket)
    send_text(socket, ~s(["1","3","room:lobby","phx_leave",{}]))
    assert {:ok, _} = recv_text(socket)
    assert Process.info(pubsub, :monitors) == {:monitors, []}

    :ok =
      Phoenix.PubSub.broadcast(
        pubsub,
        "room:lobby",
        %Phoenix.Socket.Broadcast{topic: "room:lobby", event: "probe", payload: %{}}
      )

    assert {:error, :timeout} = :gen_tcp.recv(socket, 0, 100)

    send_text(socket, ~s(["9","10","room:lobby","phx_join",{}]))
    assert {:ok, reply} = recv_text(socket)

    assert Jason.decode!(reply) == [
             "9",
             "10",
             "room:lobby",
             "phx_reply",
             %{"status" => "ok", "response" => %{}}
           ]

    assert {:monitors, [_]} = Process.info(pubsub, :monitors)
    send_text(socket, ~s(["9","11","room:lobby","phx_join",{}]))
    assert {:ok, duplicate} = recv_text(socket)

    assert Jason.decode!(duplicate) == [
             "9",
             "11",
             "room:lobby",
             "phx_reply",
             %{"status" => "error", "response" => %{"reason" => "already_joined"}}
           ]

    assert {:monitors, [_]} = Process.info(pubsub, :monitors)
    send_text(socket, ~s(["1","12","room:lobby","phx_leave",{}]))
    assert {:ok, stale_leave} = recv_text(socket)

    assert Jason.decode!(stale_leave) == [
             "1",
             "12",
             "room:lobby",
             "phx_reply",
             %{"status" => "error", "response" => %{"reason" => "unmatched_topic"}}
           ]

    assert {:monitors, [_]} = Process.info(pubsub, :monitors)

    :ok =
      Phoenix.PubSub.broadcast(
        pubsub,
        "room:lobby",
        %Phoenix.Socket.Broadcast{topic: "room:lobby", event: "probe", payload: %{}}
      )

    assert {:ok, event} = recv_text(socket)
    assert Jason.decode!(event) == [nil, nil, "room:lobby", "probe", %{}]
    assert {:error, :timeout} = :gen_tcp.recv(socket, 0, 100)
  end

  defp send_text(socket, payload) do
    mask = <<1, 2, 3, 4>>

    encoded =
      payload
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.map(fn {byte, i} -> Bitwise.bxor(byte, :binary.at(mask, rem(i, 4))) end)
      |> :erlang.list_to_binary()

    length = byte_size(payload)
    header = if length < 126, do: <<0x81, 0x80 + length>>, else: <<0x81, 0xFE, length::16>>
    :gen_tcp.send(socket, <<header::binary, mask::binary, encoded::binary>>)
  end

  defp recv_text(socket) do
    with {:ok, <<0x81, marker>>} <- :gen_tcp.recv(socket, 2, 1_000),
         {:ok, length} <- recv_length(socket, marker),
         {:ok, payload} <- :gen_tcp.recv(socket, length, 1_000) do
      {:ok, payload}
    end
  end

  defp recv_length(_socket, length) when length < 126, do: {:ok, length}

  defp recv_length(socket, 126) do
    with {:ok, <<length::16>>} <- :gen_tcp.recv(socket, 2, 1_000), do: {:ok, length}
  end

  defp recv_length(socket, 127) do
    with {:ok, <<length::64>>} <- :gen_tcp.recv(socket, 8, 1_000), do: {:ok, length}
  end

  test "rejects the upgrade with 404 for a socket module without connect/3" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, pid} =
      Task.start(fn ->
        Phoenix.AtomVM.run(
          Phoenix.AtomVM.WebSocketTest.Router,
          port: port,
          static: [],
          socket: {"/ws", Phoenix.AtomVM.WebSocketTest.NoConnectSocket}
        )
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    {:ok, socket} = connect(port, 30)

    :ok =
      :gen_tcp.send(
        socket,
        "GET /ws HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
      )

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    assert response =~ "HTTP/1.1 404"
    :ok = :gen_tcp.close(socket)
  end

  defp upgrade_request do
    "GET /socket/websocket HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
  end

  defp recv_headers(socket, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [headers, rest] ->
        {:ok, headers, rest}

      [_] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 1_000)
        recv_headers(socket, acc <> data)
    end
  end

  defp connect(_port, 0), do: flunk("WebSocket test listener did not start")

  defp connect(port, attempts) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 100) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, :econnrefused} ->
        Process.sleep(20)
        connect(port, attempts - 1)

      other ->
        other
    end
  end
end
