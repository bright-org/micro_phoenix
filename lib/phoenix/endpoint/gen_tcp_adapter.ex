defmodule Phoenix.Endpoint.GenTCPAdapter do
  @moduledoc false
  @behaviour Plug.Conn.Adapter

  defstruct status: nil, headers: [], body: "", request_body: ""

  @impl true
  def send_resp(payload, status, headers, body) do
    body = IO.iodata_to_binary(body)
    {:ok, body, %{payload | status: status, headers: headers, body: body}}
  end

  @impl true
  def send_file(payload, status, headers, path, offset, length) do
    {:ok, file} = Phoenix.AtomVM.PrivFile.read(path)
    size = byte_size(file)
    length = if length == :all, do: size - offset, else: length
    body = binary_part(file, offset, length)
    {:ok, body, %{payload | status: status, headers: headers, body: body}}
  end

  @impl true
  def send_chunked(payload, status, headers) do
    {:ok, nil, %{payload | status: status, headers: headers}}
  end

  @impl true
  def chunk(payload, chunk) do
    body = IO.iodata_to_binary([payload.body || "", chunk])
    {:ok, chunk, %{payload | body: body}}
  end

  @impl true
  def read_req_body(%{request_body: body} = payload, opts) do
    length = Keyword.get(opts, :length, 8_000_000)

    if byte_size(body) > length do
      {:more, binary_part(body, 0, length),
       %{payload | request_body: binary_part(body, length, byte_size(body) - length)}}
    else
      {:ok, body, %{payload | request_body: ""}}
    end
  end

  @impl true
  def push(payload, _path, _headers), do: {:error, payload}

  @impl true
  def inform(payload, _status, _headers), do: {:ok, payload}

  @impl true
  def upgrade(payload, _protocol, _opts), do: {:ok, payload}

  @impl true
  def get_peer_data(_payload), do: %{address: {127, 0, 0, 1}, port: 0, ssl_cert: nil}

  @impl true
  def get_sock_data(_payload), do: %{address: {127, 0, 0, 1}, port: 0}

  @impl true
  def get_ssl_data(_payload), do: nil

  @impl true
  def get_http_protocol(_payload), do: :"HTTP/1.1"
end
