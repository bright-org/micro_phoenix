defmodule Phoenix.Endpoint do
  @moduledoc false

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote bind_quoted: [otp_app: otp_app] do
      @behaviour Plug

      use Plug.Builder, otp_app: otp_app

      import Phoenix.Endpoint

      Module.register_attribute(__MODULE__, :phoenix_sockets, accumulate: true, persist: false)

      @otp_app otp_app

      var!(code_reloading?) = Application.compile_env(@otp_app, [__MODULE__, :code_reloader], false)
      _ = var!(code_reloading?)

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        Phoenix.Endpoint.Supervisor.start_link(__MODULE__, Keyword.put(opts, :otp_app, @otp_app))
      end

      def code_reloading? do
        Application.get_env(@otp_app, __MODULE__)[:code_reloader] == true
      end

      def config_change(_changed, _removed), do: :ok
    end
  end

  defmacro socket(path, module, opts \\ []) do
    quote do
      @phoenix_sockets {unquote(path), unquote(module), unquote(opts)}
    end
  end
end

defmodule Phoenix.Endpoint.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(endpoint, opts) do
    Supervisor.start_link(__MODULE__, {endpoint, opts}, name: module_name(endpoint))
  end

  def init({endpoint, opts}) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    config =
      otp_app
      |> Application.get_env(endpoint, [])
      |> Keyword.merge(opts)

    port = config |> Keyword.get(:http, []) |> Keyword.get(:port, 8080)
    server? = Keyword.get(config, :server, true)

    children =
      if server? do
        [{Phoenix.Endpoint.Server, plug: {endpoint, []}, port: port}]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp module_name(endpoint), do: Module.concat(endpoint, Supervisor)
end

defmodule Phoenix.Endpoint.Server do
  @moduledoc false
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    plug = Keyword.fetch!(opts, :plug)
    port = Keyword.get(opts, :port, 8080)

    {:ok, listen_sock} =
      :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, packet: :raw])

    state = %{listen_sock: listen_sock, plug: plug, port: port}
    spawn_link(fn -> accept_loop(state) end)
    IO.puts("Phoenix HTTP Server listening on http://localhost:#{port}/")
    {:ok, state}
  end

  defp accept_loop(%{listen_sock: listen_sock, plug: {endpoint, endpoint_opts}} = state) do
    case :gen_tcp.accept(listen_sock) do
      {:ok, client} ->
        spawn(fn -> serve(client, endpoint, endpoint_opts) end)
        accept_loop(state)

      {:error, _} ->
        accept_loop(state)
    end
  end

  defp serve(socket, endpoint, endpoint_opts) do
    try do
      with {:ok, data} <- :gen_tcp.recv(socket, 0),
           {:ok, response} <- dispatch(data, endpoint, endpoint_opts) do
        :gen_tcp.send(socket, response)
      else
        _ -> :gen_tcp.send(socket, encode_raw(500, "Internal Server Error"))
      end
    rescue
      e ->
        IO.puts(:stderr, Exception.format(:error, e, __STACKTRACE__))
        :gen_tcp.send(socket, encode_raw(500, "Internal Server Error"))
    after
      :gen_tcp.close(socket)
    end
  end

  @doc false
  def dispatch(data, endpoint, endpoint_opts \\ []) when is_binary(data) do
    with {:ok, conn} <- build_conn(data),
         conn when is_map(conn) <- endpoint.call(conn, endpoint_opts) do
      {:ok, encode_response(conn)}
    else
      _ -> {:error, :dispatch_failed}
    end
  end

  @doc false
  def dispatch_router(data, router, router_opts \\ []) when is_binary(data) do
    with {:ok, conn} <- build_conn(data) do
      static_opts = Keyword.get(router_opts, :static, [])

      case Phoenix.Static.try_serve(conn, static_opts) do
        {:ok, conn} ->
          {:ok, encode_response(conn)}

        :miss ->
          case router.call(conn, Keyword.delete(router_opts, :static)) do
            conn when is_map(conn) -> {:ok, encode_response(conn)}
            _ -> {:error, :dispatch_failed}
          end
      end
    else
      _ -> {:error, :dispatch_failed}
    end
  end

  defp encode_raw(status, body) do
    [
      "HTTP/1.1 #{status} #{status_message(status)}",
      "content-type: text/plain",
      "content-length: #{byte_size(body)}",
      "",
      body
    ]
    |> Enum.join("\r\n")
  end

  defp build_conn(data) do
    case Phoenix.Binary.split2(data, "\r\n\r\n") do
      [header_part, body] ->
        [request_line | headers] = Phoenix.Binary.split(header_part, "\r\n")

        case Phoenix.Binary.split(request_line, " ") do
          [method, target | _rest] ->
            {path, query} = split_target(target)
            method = Phoenix.Binary.upcase_ascii(method)
            req_headers = parse_headers(headers)
            body_params = parse_body_params(req_headers, body)

            conn = %Plug.Conn{
              adapter: {Phoenix.Endpoint.GenTCPAdapter, %Phoenix.Endpoint.GenTCPAdapter{}},
              method: override_method(method, body_params),
              request_path: path,
              path_info: Phoenix.Binary.split_trim(path, "/"),
              query_string: query,
              req_headers: req_headers,
              body_params: Map.delete(body_params, "_method"),
              params: Map.delete(body_params, "_method"),
              scheme: :http,
              host: "localhost",
              port: 4000,
              remote_ip: {127, 0, 0, 1}
            }

            {:ok, conn}

          _ ->
            {:error, :invalid_request}
        end

      _ ->
        {:error, :invalid_request}
    end
  rescue
    ArgumentError -> {:error, :invalid_method}
  end

  # Browser forms send POST + `_method` for PUT/PATCH/DELETE.
  defp override_method(method, %{"_method" => override}) when is_binary(override) do
    case Phoenix.Binary.upcase_ascii(override) do
      m when m in ["PUT", "PATCH", "DELETE"] -> m
      _ -> method
    end
  end

  defp override_method(method, _params), do: method

  defp split_target(target) do
    case Phoenix.Binary.split2(target, "?") do
      [path, query] -> {path, query}
      [path] -> {path, ""}
    end
  end

  defp parse_headers(headers) do
    Enum.map(headers, fn line ->
      case Phoenix.Binary.split2(line, ": ") do
        [k, v] -> {Phoenix.Binary.downcase_ascii(k), v}
        [k] -> {Phoenix.Binary.downcase_ascii(k), ""}
        _ -> {line, ""}
      end
    end)
  end

  defp parse_body_params(headers, body) do
    content_type =
      headers
      |> Enum.find_value("", fn
        {"content-type", rest} -> rest
        _ -> false
      end)

    if Phoenix.Binary.starts_with?(content_type, "application/x-www-form-urlencoded") do
      decode_form_body(body)
    else
      %{}
    end
  end

  # Minimal x-www-form-urlencoded decoder (no URI / String / Regex).
  defp decode_form_body(body) when is_binary(body) do
    body
    |> Phoenix.Binary.split("&")
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn pair, acc ->
      case Phoenix.Binary.split2(pair, "=") do
        [key, value] ->
          put_nested(acc, parse_key_path(url_decode(key)), url_decode(value))

        [key] ->
          put_nested(acc, parse_key_path(url_decode(key)), "")

        _ ->
          acc
      end
    end)
  end

  defp url_decode(bin) when is_binary(bin) do
    url_decode(bin, <<>>)
  end

  defp url_decode(<<"+", rest::binary>>, acc), do: url_decode(rest, <<acc::binary, ?\s>>)

  defp url_decode(<<"%", h1, h2, rest::binary>>, acc) do
    case {hex_val(h1), hex_val(h2)} do
      {v1, v2} when is_integer(v1) and is_integer(v2) ->
        url_decode(rest, <<acc::binary, (v1 * 16 + v2)>>)

      _ ->
        url_decode(<<h1, h2, rest::binary>>, <<acc::binary, ?%>>)
    end
  end

  defp url_decode(<<c, rest::binary>>, acc), do: url_decode(rest, <<acc::binary, c>>)
  defp url_decode(<<>>, acc), do: acc

  defp hex_val(c) when c in ?0..?9, do: c - ?0
  defp hex_val(c) when c in ?a..?f, do: c - ?a + 10
  defp hex_val(c) when c in ?A..?F, do: c - ?A + 10
  defp hex_val(_), do: nil

  # Convert flat "post[title]" keys into %{"post" => %{"title" => ...}}.
  defp nest_params(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      put_nested(acc, parse_key_path(key), value)
    end)
  end

  defp parse_key_path(key) when is_binary(key) do
    case Phoenix.Binary.split2(key, "[") do
      [head] ->
        [head]

      [head, rest] ->
        brackets =
          rest
          |> Phoenix.Binary.split("]")
          |> Enum.flat_map(fn
            "" -> []
            part -> Phoenix.Binary.split_trim(part, "[")
          end)

        [head | brackets]
    end
  end

  defp put_nested(map, [key], value) when is_map(map) do
    Map.put(map, key, value)
  end

  defp put_nested(map, [key | rest], value) when is_map(map) do
    child = Map.get(map, key, %{})
    child = if is_map(child), do: child, else: %{}
    Map.put(map, key, put_nested(child, rest, value))
  end

  defp encode_response(%Plug.Conn{} = conn) do
    {status, headers, body} = response_parts(conn)
    body = if is_binary(body), do: body, else: IO.iodata_to_binary(body || "")
    headers = put_content_length(headers, body)
    header_lines = Enum.map(headers, fn {k, v} -> "#{k}: #{v}" end)

    ["HTTP/1.1 #{status} #{status_message(status)}", header_lines, "", body]
    |> List.flatten()
    |> Enum.join("\r\n")
  end

  defp response_parts(%Plug.Conn{adapter: {_mod, %{status: status, headers: headers, body: body}}})
       when not is_nil(status) do
    {status, headers, body}
  end

  defp response_parts(%Plug.Conn{status: status, resp_headers: headers, resp_body: body}) do
    {status || 200, headers, body || ""}
  end

  defp put_content_length(headers, body) do
    headers =
      Enum.reject(headers, fn {k, _} ->
        Phoenix.Binary.downcase_ascii(to_string(k)) == "content-length"
      end)

    [{"content-length", :erlang.integer_to_binary(byte_size(body))} | headers]
  end

  defp status_message(200), do: "OK"
  defp status_message(302), do: "Found"
  defp status_message(404), do: "Not Found"
  defp status_message(_code), do: "OK"
end
