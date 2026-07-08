defmodule MicroPhoenix.Request do
  defstruct method: :get,
            path: "/",
            headers: %{},
            body: "",
            params: %{},
            path_params: %{},
            query_params: %{},
            body_params: %{}

  def parse(data) when is_binary(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [header_block, body] ->
        parse_headers(header_block, body)

      [header_block] ->
        parse_headers(header_block, "")
    end
  end

  defp parse_headers(header_block, body) do
    lines = String.split(header_block, "\r\n")

    case lines do
      [request_line | header_lines] ->
        {method, path, query_params} = parse_request_line(request_line)
        headers = parse_header_lines(header_lines)
        body_params = decode_body_params(headers, body, method)

        method =
          case Map.get(body_params, "_method") do
            nil -> method
            value -> value |> String.downcase() |> String.to_atom()
          end

        body_params = Map.delete(body_params, "_method")

        %__MODULE__{
          method: method,
          path: normalize_path(path),
          headers: headers,
          body: body,
          query_params: query_params,
          body_params: body_params,
          params: Map.merge(query_params, body_params)
        }

      _ ->
        %__MODULE__{}
    end
  end

  defp parse_request_line(line) do
    case String.split(line, " ") do
      [method, path | _] ->
        {method |> String.downcase() |> String.to_atom(), path, parse_query_string(path)}

      _ ->
        {:get, "/", %{}}
    end
  end

  defp parse_header_lines(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.downcase(String.trim(key)), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp parse_query_string(path) do
    case String.split(path, "?", parts: 2) do
      [_path, query] -> decode_form(query)
      _ -> %{}
    end
  end

  defp normalize_path(path) do
    path
    |> String.split("?")
    |> hd()
    |> then(fn p -> if p == "", do: "/", else: p end)
  end

  defp decode_body_params(headers, body, method) when method in [:post, :put, :patch] do
    content_type = Map.get(headers, "content-type", "")

    if String.starts_with?(content_type, "application/x-www-form-urlencoded") do
      decode_form(body)
    else
      %{}
    end
  end

  defp decode_body_params(_headers, _body, _method), do: %{}

  defp decode_form(""), do: %{}

  defp decode_form(form) do
    form
    |> URI.decode_query()
    |> nest_params()
  end

  defp nest_params(flat) do
    Enum.reduce(flat, %{}, fn {key, value}, acc ->
      put_nested(acc, key, value)
    end)
  end

  defp put_nested(map, key, value) do
    case Regex.run(~r/^([^\[]+)\[(.+)\]$/, key) do
      [_, top, inner] ->
        Map.update(map, top, put_nested(%{}, inner, value), fn existing ->
          Map.merge(existing, put_nested(%{}, inner, value))
        end)

      nil ->
        Map.put(map, key, value)
    end
  end
end
