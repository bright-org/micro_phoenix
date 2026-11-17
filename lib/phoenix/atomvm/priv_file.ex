defmodule Phoenix.AtomVM.PrivFile do
  @moduledoc false

  def read(path) when is_binary(path) do
    if :erlang.function_exported(:atomvm, :read_priv, 2) do
      read_packed(path)
    else
      case File.read(path) do
        {:ok, body} -> {:ok, body}
        _ -> :error
      end
    end
  end

  defp read_packed(path) do
    case :binary.split(path, "/priv/") do
      [app, relative] when byte_size(app) > 0 and byte_size(relative) > 0 ->
        if :binary.split(app, "/") == [app] do
          body = :atomvm.read_priv(:erlang.binary_to_atom(app, :utf8), relative)
          if is_binary(body), do: {:ok, body}, else: :error
        else
          :error
        end

      _ ->
        :error
    end
  end
end
