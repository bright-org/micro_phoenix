defmodule Template do

  def render(_conn, html, assigns \\ %{}) when is_binary(html) do
    {:ok, 200, "text/html", render_template(html, assigns)}
  end

  defp render_template(template, assigns) do
    Regex.replace(~r/<%=\s*@([a-zA-Z0-9_]+)\s*%>/, template, fn _, var_name ->
      atom_key =
        try do
          :erlang.binary_to_existing_atom(var_name, :utf8)
        rescue
          ArgumentError -> nil
        end

      value =
        cond do
          atom_key != nil and Map.has_key?(assigns, atom_key) -> Map.get(assigns, atom_key)
          Map.has_key?(assigns, var_name) -> Map.get(assigns, var_name)
          true -> nil
        end

      case value do
        nil -> ""
        v when is_list(v) -> Enum.join(v, "")
        v when is_binary(v) -> v
        v -> to_string(v)
      end
    end)
  end
end
