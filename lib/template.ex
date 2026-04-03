defmodule Template do
  def render(_conn, html, assigns \\ %{}) when is_binary(html) do
    {:ok, 200, "text/html", render_template(html, assigns)}
  end

  defp render_template(template, assigns) do
    Enum.reduce(assigns, template, fn {key, value}, acc ->
      placeholder = ["<%= @", normalize_key(key), " %>"] |> IO.iodata_to_binary()
      replacement = normalize_value(value)
      :binary.replace(acc, placeholder, replacement, [:global])
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp normalize_value(nil), do: ""
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_list(value), do: IO.iodata_to_binary(value)
  defp normalize_value(value), do: to_string(value)
end
