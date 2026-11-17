defmodule MicroPhoenix.SocketLiveProbe.RoomChannel do
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

defmodule MicroPhoenix.SocketLiveProbe.Socket do
  use Phoenix.Socket
  channel("room:lobby", MicroPhoenix.SocketLiveProbe.RoomChannel)

  def connect(%{"vsn" => "2.0.0"}, socket, _connect_info) do
    {:ok, Phoenix.Socket.assign(socket, :connected, true)}
  end

  def connect(_, _, _), do: :error
end

defmodule MicroPhoenix.SocketLiveProbe.Router do
  def call(conn, _opts), do: %{conn | status: 200, resp_body: "http-ok"}
end

defmodule MicroPhoenix.SocketLiveProbe do
  def start do
    {:ok, _} = Phoenix.PubSub.start_link(name: MicroPhoenix.SocketLiveProbe.PubSub)

    Phoenix.AtomVM.run(MicroPhoenix.SocketLiveProbe.Router,
      port: 18083,
      static: [],
      socket:
        {"/socket/websocket", MicroPhoenix.SocketLiveProbe.Socket,
         pubsub: MicroPhoenix.SocketLiveProbe.PubSub}
    )
  end
end
