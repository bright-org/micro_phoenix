defmodule MicroPhoenix.Request do
  defstruct method: :get, path: "/", headers: %{}

  def parse(data) when is_binary(data) do
    request_line = read_request_line(data)

    case parse_request_line(request_line) do
      {method, path} ->
        %__MODULE__{
          method: parse_method(method),
          path: normalize_path(path)
        }

      :error ->
        %__MODULE__{}
    end
  end

  # AtomVM 互換のため、先頭行を 1 byte ずつ走査する。
  defp read_request_line(data), do: read_request_line(data, <<>>)

  defp read_request_line(<<"\r\n", _rest::binary>>, acc), do: acc
  defp read_request_line(<<char, rest::binary>>, acc), do: read_request_line(rest, <<acc::binary, char>>)
  defp read_request_line(<<>>, acc), do: acc

  defp parse_request_line(line) do
    case read_token(line) do
      {<<>>, _rest} ->
        :error

      {method, rest} ->
        case read_token(skip_spaces(rest)) do
          {<<>>, _next_rest} -> :error
          {path, _next_rest} -> {method, path}
        end
    end
  end

  defp read_token(data), do: read_token(data, <<>>)

  defp read_token(<<>>, acc), do: {acc, <<>>}
  defp read_token(<<" ", rest::binary>>, acc), do: {acc, rest}

  defp read_token(<<char, rest::binary>>, acc) do
    read_token(rest, <<acc::binary, char>>)
  end

  defp skip_spaces(<<" ", rest::binary>>), do: skip_spaces(rest)
  defp skip_spaces(rest), do: rest

  defp parse_method(method) do
    case lowercase_ascii(method, <<>>) do
      <<"get">> -> :get
      <<"post">> -> :post
      <<"put">> -> :put
      <<"patch">> -> :patch
      <<"delete">> -> :delete
      <<"head">> -> :head
      <<"options">> -> :options
      _ -> :get
    end
  end

  defp lowercase_ascii(<<char, rest::binary>>, acc) when char >= ?A and char <= ?Z do
    lowercase_ascii(rest, <<acc::binary, char + 32>>)
  end

  defp lowercase_ascii(<<char, rest::binary>>, acc) do
    lowercase_ascii(rest, <<acc::binary, char>>)
  end

  defp lowercase_ascii(<<>>, acc), do: acc

  defp normalize_path(path), do: drop_query_string(path, <<>>) |> normalize_empty_path()

  defp drop_query_string(<<"?", _rest::binary>>, acc), do: acc
  defp drop_query_string(<<char, rest::binary>>, acc), do: drop_query_string(rest, <<acc::binary, char>>)
  defp drop_query_string(<<>>, acc), do: acc

  defp normalize_empty_path(<<>>), do: "/"
  defp normalize_empty_path(path), do: path
end
