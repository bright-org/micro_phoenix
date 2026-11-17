defmodule Phoenix.EndpointSocketConfigTest do
  use ExUnit.Case, async: true

  defmodule RoomChannel do
    use Phoenix.Channel

    def join("room:lobby", _params, socket), do: {:ok, socket}
  end

  defmodule FakeSocket do
    use Phoenix.Socket

    channel("room:*", __MODULE__.Channel)

    def connect(_params, socket, _connect_info), do: {:ok, socket}
  end

  defmodule FakeSocket.Channel do
    use Phoenix.Channel

    def join(_topic, _params, socket), do: {:ok, socket}
  end

  defmodule NoSockets do
    use Phoenix.Endpoint, otp_app: :micro_phoenix
  end

  defmodule WithSockets do
    use Phoenix.Endpoint, otp_app: :micro_phoenix

    socket("/socket", Phoenix.EndpointSocketConfigTest.FakeSocket,
      pubsub: Some.PubSub,
      timeout: 10_000
    )

    socket("/live", Phoenix.EndpointSocketConfigTest.FakeSocket)
  end

  test "__phoenix_sockets__/0 exposes declared sockets in declaration order" do
    assert WithSockets.__phoenix_sockets__() == [
             {"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket,
              pubsub: Some.PubSub, timeout: 10_000},
             {"/live", Phoenix.EndpointSocketConfigTest.FakeSocket, []}
           ]

    assert NoSockets.__phoenix_sockets__() == []
  end

  test "socket_run_opts keeps compiled socket modules and skips the rest" do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    try do
      assert Mix.Tasks.Phoenix.Atomvm.Packbeam.socket_run_opts(nil) == []

      assert Mix.Tasks.Phoenix.Atomvm.Packbeam.socket_run_opts(WithSockets) == [
               {"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket,
                pubsub: Some.PubSub, timeout: 10_000},
               {"/live", Phoenix.EndpointSocketConfigTest.FakeSocket, []}
             ]

      defmodule UnavailableSocket do
        use Phoenix.Endpoint, otp_app: :micro_phoenix

        socket("/live", Some.Missing.Socket)
        socket("/socket", Phoenix.EndpointSocketConfigTest.FakeSocket)
      end

      assert Mix.Tasks.Phoenix.Atomvm.Packbeam.socket_run_opts(UnavailableSocket) == [
               {"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket, []}
             ]

      assert_received {:mix_shell, :info, [message]}
      assert message =~ "Some.Missing.Socket"
    after
      Mix.shell(previous_shell)
    end
  end

  test "socket_target matches single tuples and lists with exact path or /websocket suffix" do
    request = "GET /socket/websocket?vsn=2.0.0 HTTP/1.1\r\nUpgrade: websocket\r\n\r\n"

    assert Phoenix.AtomVM.socket_target(request, nil) == :http

    assert Phoenix.AtomVM.socket_target(
             request,
             {"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket}
           ) == {:socket, Phoenix.EndpointSocketConfigTest.FakeSocket, []}

    assert Phoenix.AtomVM.socket_target(request, [
             {"/live", Phoenix.EndpointSocketConfigTest.FakeSocket},
             {"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket, pubsub: Some.PubSub}
           ]) == {:socket, Phoenix.EndpointSocketConfigTest.FakeSocket, pubsub: Some.PubSub}

    assert Phoenix.AtomVM.socket_target(
             "GET /other HTTP/1.1\r\n\r\n",
             [{"/socket", Phoenix.EndpointSocketConfigTest.FakeSocket}]
           ) == :http
  end
end
