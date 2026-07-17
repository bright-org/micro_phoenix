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
    case Phoenix.Binary.split2(data, "\r\n\r\n") do
      [header_block, body] ->
        parse_headers(header_block, body)

      [header_block] ->
        parse_headers(header_block, "")
    end
  end

  defp parse_headers(header_block, body) do
    lines = Phoenix.Binary.split(header_block, "\r\n")

    case lines do
      [request_line | header_lines] ->
        {method, path, query_params} = parse_request_line(request_line)
        headers = parse_header_lines(header_lines)
        body_params = decode_body_params(headers, body, method)

        method =
          case Map.get(body_params, "_method") do
            nil -> method
            value -> Phoenix.Binary.http_method_atom(value)
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
    case Phoenix.Binary.split(line, " ") do
      [method, path | _] ->
        {Phoenix.Binary.http_method_atom(method), path, parse_query_string(path)}

      _ ->
        {:get, "/", %{}}
    end
  end

  defp parse_header_lines(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case Phoenix.Binary.split2(line, ":") do
        [key, value] ->
          Map.put(acc, Phoenix.Binary.downcase_ascii(trim_key(key)), trim_value(value))

        _ ->
          acc
      end
    end)
  end

  defp trim_key(key) when is_binary(key), do: key |> trim_leading() |> trim_trailing()

  defp trim_value(value) when is_binary(value), do: trim_leading(value)

  defp trim_leading(<<" ", rest::binary>>), do: trim_leading(rest)
  defp trim_leading(<<"\t", rest::binary>>), do: trim_leading(rest)
  defp trim_leading(bin), do: bin

  defp trim_trailing(bin) do
    size = byte_size(bin)

    if size > 0 do
      last = :binary.at(bin, size - 1)

      if last == ?\s do
        trim_trailing(binary_part(bin, 0, size - 1))
      else
        bin
      end
    else
      bin
    end
  end

  defp parse_query_string(path) do
    case Phoenix.Binary.split2(path, "?") do
      [_path, query] -> decode_form(query)
      _ -> %{}
    end
  end

  defp normalize_path(path) do
    case Phoenix.Binary.split2(path, "?") do
      [p, _query] -> if p == "", do: "/", else: p
      [p] -> if p == "", do: "/", else: p
    end
  end

  defp decode_body_params(headers, body, method) when method in [:post, :put, :patch] do
    content_type = Map.get(headers, "content-type", "")

    if Phoenix.Binary.starts_with?(content_type, "application/x-www-form-urlencoded") do
      decode_form(body)
    else
      %{}
    end
  end

  defp decode_body_params(_headers, _body, _method), do: %{}

  defp decode_form(""), do: %{}

  defp decode_form(form) do
    form
    |> Phoenix.Binary.split("&")
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn pair, acc ->
      case Phoenix.Binary.split2(pair, "=") do
        [key, value] -> Map.put(acc, key, value)
        [key] -> Map.put(acc, key, "")
        _ -> acc
      end
    end)
    |> nest_params()
  end

  defp nest_params(flat) do
    Enum.reduce(flat, %{}, fn {key, value}, acc ->
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

  defp put_nested(map, [key], value), do: Map.put(map, key, value)

  defp put_nested(map, [key | rest], value) do
    child = Map.get(map, key, %{})
    child = if is_map(child), do: child, else: %{}
    Map.put(map, key, put_nested(child, rest, value))
  end
end
