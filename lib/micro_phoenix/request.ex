defmodule MicroPhoenix.Request do
  defstruct method: :get, path: "/", headers: %{}

  def parse(data) when is_binary(data) do
    case request_line(data) do
      nil ->
        %__MODULE__{}

      line ->
        parse_request_line(line)
    end
  end

  defp request_line(data) do
    case :binary.split(data, "\r\n") do
      [line, _rest] -> line
      [line] -> line
    end
  end

  defp parse_request_line(line) do
    case :binary.split(line, " ", [:global]) do
      [method, path | _] ->
        %__MODULE__{
          method: method_atom(method),
          path: normalize_path(path)
        }

      _ ->
        %__MODULE__{}
    end
  end

  defp method_atom("GET"), do: :get
  defp method_atom("POST"), do: :post
  defp method_atom("PUT"), do: :put
  defp method_atom("PATCH"), do: :patch
  defp method_atom("DELETE"), do: :delete
  defp method_atom("HEAD"), do: :head
  defp method_atom("OPTIONS"), do: :options
  defp method_atom(_method), do: :unknown

  defp normalize_path(path) do
    normalized =
      case :binary.split(path, "?") do
        [prefix, _query] -> prefix
        [prefix] -> prefix
      end

    case normalized do
      "" -> "/"
      _ -> normalized
    end
  end
end
