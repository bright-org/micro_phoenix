defmodule MicroPhoenix.Request do
  defstruct method: :get, path: "/", headers: %{}

  def parse(data) when is_binary(data) do
    case String.split(data, "\r\n") do
      [request_line | _rest] ->
        case String.split(request_line, " ") do
          [method, path | _] ->
            %__MODULE__{
              method: method |> String.downcase() |> String.to_atom(),
              path: normalize_path(path)
            }

          _ ->
            %__MODULE__{}
        end

      _ ->
        %__MODULE__{}
    end
  end

  defp normalize_path(path) do
    path
    |> String.split("?")
    |> hd()
    |> then(fn p -> if p == "", do: "/", else: p end)
  end
end
