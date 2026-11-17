defmodule Phoenix.Endpoint.PlugPathTest do
  use ExUnit.Case

  defmodule MarkerPlug do
    def init(opts), do: opts

    def call(conn, _opts) do
      Plug.Conn.put_resp_header(conn, "x-endpoint-plug", "before-router")
    end
  end

  defmodule HaltPlug do
    def init(opts), do: opts

    def call(%Plug.Conn{request_path: "/halt"} = conn, _opts) do
      conn
      |> Plug.Conn.send_resp(403, "stopped")
      |> Plug.Conn.halt()
    end

    def call(conn, _opts), do: conn
  end

  defmodule Controller do
    def show(conn, %{"id" => id}) do
      body = "item-" <> id <> "-" <> Map.get(conn.params, "sort", "none")
      Plug.Conn.send_resp(conn, 200, body)
    end

    def create(conn, %{"id" => id}) do
      body = "item-" <> id <> "-" <> Map.get(conn.params, "name", "missing")
      Plug.Conn.send_resp(conn, 200, body)
    end
  end

  defmodule Router do
    use Phoenix.Router
    get("/items/:id", Phoenix.Endpoint.PlugPathTest.Controller, :show)
    post("/items/:id", Phoenix.Endpoint.PlugPathTest.Controller, :create)
    put("/items/:id", Phoenix.Endpoint.PlugPathTest.Controller, :create)
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :micro_phoenix
    plug(Plug.RequestId)
    plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

    plug(Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Jason
    )

    plug(Phoenix.Endpoint.PlugPathTest.MarkerPlug)
    plug(Phoenix.Endpoint.PlugPathTest.HaltPlug)
    plug(Phoenix.Endpoint.PlugPathTest.Router)
  end

  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {event, measurements, metadata})
  end

  test "GenTCPAdapter sends the requested file bytes and range" do
    path = Path.join(System.tmp_dir!(), "endpoint-file-#{System.unique_integer([:positive])}")
    File.write!(path, "abcdef")
    on_exit(fn -> File.rm(path) end)

    payload = %Phoenix.Endpoint.GenTCPAdapter{}

    assert {:ok, "abcdef", %{body: "abcdef"}} =
             Phoenix.Endpoint.GenTCPAdapter.send_file(payload, 200, [], path, 0, :all)

    assert {:ok, "bcd", %{body: "bcd"}} =
             Phoenix.Endpoint.GenTCPAdapter.send_file(payload, 206, [], path, 1, 3)
  end

  test "Endpoint Plug chain runs before Router and preserves route parameters" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /items/42 HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "x-endpoint-plug: before-router\r\n"
    assert response =~ "item-42"
  end

  test "Endpoint Plug.Parsers merges GET query parameters with route parameters" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /items/42?sort=asc HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "item-42-asc"
  end

  test "Endpoint Plug.Parsers parses a JSON POST body and retains route parameters" do
    body = ~s({"name":"Nana"})

    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "item-42-Nana"
  end

  test "Endpoint Plug.Parsers rejects invalid UTF-8 in a URL-encoded POST" do
    body = "name=%FF"

    assert_raise Plug.Parsers.BadEncodingError, fn ->
      Phoenix.Endpoint.Server.dispatch(
        "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/x-www-form-urlencoded\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}",
        Endpoint
      )
    end
  end

  test "Endpoint preserves form _method override while Plug.Parsers decodes the body" do
    body = "_method=PUT&name=Nana+One"

    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/x-www-form-urlencoded\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "item-42-Nana One"
  end

  test "router-only dispatch preserves form parameters and _method override" do
    body = "_method=PUT&name=Nana+One"

    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch_router(
               "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/x-www-form-urlencoded\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}",
               Router,
               static: []
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "item-42-Nana One"
  end

  test "the Endpoint adapter reads a request body in bounded chunks" do
    conn = %Plug.Conn{
      adapter:
        {Phoenix.Endpoint.GenTCPAdapter, %Phoenix.Endpoint.GenTCPAdapter{request_body: "123456"}}
    }

    assert {:more, "1234", conn} = Plug.Conn.read_body(conn, length: 4)
    assert {:ok, "56", conn} = Plug.Conn.read_body(conn, length: 4)
    assert {:ok, "", _conn} = Plug.Conn.read_body(conn, length: 4)
  end

  test "a halted Endpoint Plug skips the Router" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /halt HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Endpoint
             )

    assert response =~ "HTTP/1.1 403 Forbidden\r\n"
    assert response =~ "stopped"
  end

  test "Endpoint Plug.RequestId forwards a valid request header" do
    id = "12345678901234567890"

    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /items/42 HTTP/1.1\r\nhost: localhost\r\nx-request-id: #{id}\r\n\r\n",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "x-request-id: #{id}\r\n"
  end

  test "Endpoint Plug.RequestId generates an ID when absent" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /items/42 HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Endpoint
             )

    assert [_, id] = Regex.run(~r/x-request-id: ([^\r\n]+)/, response)
    assert byte_size(id) in 20..200
  end

  test "Endpoint Plug.Telemetry emits start and stop with connection metadata" do
    handler = "endpoint-plug-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler,
        [[:phoenix, :endpoint, :start], [:phoenix, :endpoint, :stop]],
        &__MODULE__.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch(
               "GET /items/42 HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Endpoint
             )

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert_receive {[:phoenix, :endpoint, :start], %{system_time: start_time}, start_metadata}
    assert is_integer(start_time)
    assert start_metadata.options == []
    assert %Plug.Conn{request_path: "/items/42"} = start_metadata.conn

    assert_receive {[:phoenix, :endpoint, :stop], %{duration: duration}, stop_metadata}
    assert is_integer(duration) and duration >= 0
    assert stop_metadata.options == []
    assert %Plug.Conn{status: 200} = stop_metadata.conn
  end

  test "AtomVM HTTP loop dispatches through the Endpoint rather than directly to Router" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      Task.start(fn -> Phoenix.AtomVM.run(Router, endpoint: Endpoint, port: port, static: []) end)

    on_exit(fn -> Process.exit(server, :kill) end)

    {:ok, socket} = connect(port, 30)
    :ok = :gen_tcp.send(socket, "GET /items/42 HTTP/1.1\r\nhost: localhost\r\n\r\n")
    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    :ok = :gen_tcp.close(socket)

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "x-endpoint-plug: before-router\r\n"
    assert response =~ "item-42"
  end

  test "AtomVM HTTP loop waits for a fragmented JSON request body" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      Task.start(fn -> Phoenix.AtomVM.run(Router, endpoint: Endpoint, port: port, static: []) end)

    on_exit(fn -> Process.exit(server, :kill) end)

    {:ok, socket} = connect(port, 30)
    body = ~s({"name":"Nana"})
    :ok = :gen_tcp.send(socket, "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-ty")

    :ok =
      :gen_tcp.send(
        socket,
        "pe: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n{\"name\":"
      )

    assert {:error, :timeout} = :gen_tcp.recv(socket, 0, 50)
    :ok = :gen_tcp.send(socket, "\"Nana\"}")
    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    :ok = :gen_tcp.close(socket)

    assert response =~ "HTTP/1.1 200 OK\r\n"
    assert response =~ "item-42-Nana"
  end

  test "AtomVM HTTP loop does not count JSON body bytes against the header limit" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      Task.start(fn -> Phoenix.AtomVM.run(Router, endpoint: Endpoint, port: port, static: []) end)

    on_exit(fn -> Process.exit(server, :kill) end)

    {:ok, socket} = connect(port, 30)
    body = ~s({"name":"#{String.duplicate("x", 70_000)}"})

    :ok =
      :gen_tcp.send(
        socket,
        "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
      )

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    :ok = :gen_tcp.close(socket)
    assert response =~ "HTTP/1.1 200 OK\r\n"
  end

  test "AtomVM HTTP loop still rejects an oversized request header" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      Task.start(fn -> Phoenix.AtomVM.run(Router, endpoint: Endpoint, port: port, static: []) end)

    on_exit(fn -> Process.exit(server, :kill) end)

    {:ok, socket} = connect(port, 30)

    :ok =
      :gen_tcp.send(
        socket,
        "GET /items/42 HTTP/1.1\r\nx-large: #{String.duplicate("x", 70_000)}\r\n\r\n"
      )

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
    :ok = :gen_tcp.close(socket)
  end

  test "AtomVM HTTP loop returns Plug exception status for invalid form encoding" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listener)
    :ok = :gen_tcp.close(listener)

    {:ok, server} =
      Task.start(fn -> Phoenix.AtomVM.run(Router, endpoint: Endpoint, port: port, static: []) end)

    on_exit(fn -> Process.exit(server, :kill) end)

    {:ok, socket} = connect(port, 30)
    body = "name=%FF"

    :ok =
      :gen_tcp.send(
        socket,
        "POST /items/42 HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/x-www-form-urlencoded\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
      )

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 1_000)
    :ok = :gen_tcp.close(socket)

    assert response =~ "HTTP/1.1 400 Bad Request\r\n"
    refute response =~ "invalid UTF-8"
  end

  defp connect(_port, 0), do: {:error, :timeout}

  defp connect(port, retries) do
    case :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 1_000) do
      {:ok, socket} ->
        {:ok, socket}

      _ ->
        Process.sleep(20)
        connect(port, retries - 1)
    end
  end
end
