defmodule Phoenix.ConnTest do
  @moduledoc false

  import ExUnit.Assertions

  def build_conn do
    Plug.Test.conn(:get, "/")
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
  end

  def build_conn(method, path, params_or_body \\ nil) do
    Plug.Test.conn(method, path, params_or_body)
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
  end

  defmacro get(conn, path_or_action, params_or_body \\ nil) do
    quote do
      Phoenix.ConnTest.dispatch(
        unquote(conn),
        @endpoint,
        :get,
        unquote(path_or_action),
        unquote(params_or_body)
      )
    end
  end

  defmacro post(conn, path_or_action, params_or_body \\ nil) do
    quote do
      Phoenix.ConnTest.dispatch(
        unquote(conn),
        @endpoint,
        :post,
        unquote(path_or_action),
        unquote(params_or_body)
      )
    end
  end

  defmacro put(conn, path_or_action, params_or_body \\ nil) do
    quote do
      Phoenix.ConnTest.dispatch(
        unquote(conn),
        @endpoint,
        :put,
        unquote(path_or_action),
        unquote(params_or_body)
      )
    end
  end

  defmacro patch(conn, path_or_action, params_or_body \\ nil) do
    quote do
      Phoenix.ConnTest.dispatch(
        unquote(conn),
        @endpoint,
        :patch,
        unquote(path_or_action),
        unquote(params_or_body)
      )
    end
  end

  defmacro delete(conn, path_or_action, params_or_body \\ nil) do
    quote do
      Phoenix.ConnTest.dispatch(
        unquote(conn),
        @endpoint,
        :delete,
        unquote(path_or_action),
        unquote(params_or_body)
      )
    end
  end

  def dispatch(conn, endpoint, method, path, params_or_body) do
    endpoint = expand_endpoint(endpoint)

    conn =
      conn
      |> recycle_if_needed()
      |> Map.put(:method, method |> to_string() |> String.upcase())
      |> put_path(path)
      |> put_params(params_or_body)
      |> Plug.Conn.put_private(:phoenix_endpoint, endpoint)

    endpoint.call(conn, endpoint.init([]))
  end

  # ConnCase sets `@endpoint MyAppWeb.Endpoint` inside `quote`, so the attribute may
  # still be an aliases AST instead of a module atom.
  defp expand_endpoint(endpoint) when is_atom(endpoint), do: endpoint

  defp expand_endpoint({:__aliases__, _, parts}) when is_list(parts) do
    Module.concat(parts)
  end

  def html_response(conn, status) do
    body = response(conn, status)
    _ = content_type_match!(conn, "text/html")
    body
  end

  def json_response(conn, status) do
    body = response(conn, status)
    _ = content_type_match!(conn, "application/json")
    Jason.decode!(body)
  end

  def response(%Plug.Conn{state: :unset}, _status) do
    raise "expected connection to have a response but no response was set/sent"
  end

  def response(%Plug.Conn{status: status, resp_body: body}, given) do
    assert_status!(status, given)
    body || ""
  end

  def redirected_to(conn, status \\ 302) do
    _ = response(conn, status)

    location =
      Enum.find_value(conn.resp_headers, fn
        {key, value} -> if String.downcase(key) == "location", do: value
        _ -> nil
      end)

    location || flunk("expected connection to be redirected, but location header was missing")
  end

  def redirected_params(conn, status \\ 302) do
    location = redirected_to(conn, status)
    %URI{path: path} = URI.parse(location)

    case path |> to_string() |> String.split("/", trim: true) |> Enum.reverse() do
      [id | _] -> %{id: id}
      _ -> %{}
    end
  end

  def recycle(conn, headers \\ ~w(accept accept-language authorization)) do
    build_conn()
    |> Map.put(:host, conn.host)
    |> Map.put(:remote_ip, conn.remote_ip)
    |> Plug.Test.recycle_cookies(conn)
    |> copy_headers(conn.req_headers, headers)
  end

  def assert_error_sent(status_int_or_atom, func) when is_function(func, 0) do
    expected = Plug.Conn.Status.code(status_int_or_atom)

    {status, body} =
      try do
        func.()
        flunk("expected error to be sent, but no error was raised")
      rescue
        e ->
          if no_results_error?(e) do
            {404, Exception.message(e)}
          else
            reraise e, __STACKTRACE__
          end
      end

    assert status == expected,
           "expected error status #{expected}, got #{inspect(status)} with body:\n#{inspect(body)}"

    {status, [], body}
  end

  defp no_results_error?(e) do
    e.__struct__
    |> Module.split()
    |> List.last()
    |> Kernel.==("NoResultsError")
  end

  defp recycle_if_needed(%Plug.Conn{state: :unset} = conn), do: conn
  defp recycle_if_needed(conn), do: recycle(conn)

  defp put_path(conn, path) when is_binary(path) do
    {path, query} =
      case String.split(path, "?", parts: 2) do
        [path, query] -> {path, query}
        [path] -> {path, ""}
      end

    query_params = Plug.Conn.Query.decode(query)

    %{
      conn
      | request_path: path,
        path_info: String.split(path, "/", trim: true),
        query_string: query,
        query_params: query_params,
        params: query_params
    }
  end

  defp put_params(conn, nil), do: conn

  defp put_params(conn, params) when is_map(params) or is_list(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), normalize_param(v)} end)
    %{conn | body_params: params, params: Map.merge(conn.params || %{}, params)}
  end

  defp put_params(conn, body) when is_binary(body) do
    %{conn | body_params: body}
  end

  defp normalize_param(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_param(v)} end)
  end

  defp normalize_param(list) when is_list(list), do: Enum.map(list, &normalize_param/1)
  defp normalize_param(other), do: other

  defp copy_headers(conn, headers, copy) do
    kept = for {k, v} <- headers, k in copy, do: {k, v}
    %{conn | req_headers: kept ++ conn.req_headers}
  end

  defp content_type_match!(conn, expected) do
    type =
      case Plug.Conn.get_resp_header(conn, "content-type") do
        [value | _] -> value
        _ -> ""
      end

    unless String.contains?(type, expected) do
      flunk("expected content-type #{inspect(expected)}, got #{inspect(type)}")
    end

    type
  end

  defp assert_status!(nil, given) do
    flunk("expected response with status #{given}, but status was nil")
  end

  defp assert_status!(status, given) when is_integer(given) do
    assert status == given, "expected response with status #{given}, got #{status}"
  end

  defp assert_status!(status, given) when is_atom(given) do
    assert_status!(status, Plug.Conn.Status.code(given))
  end
end
