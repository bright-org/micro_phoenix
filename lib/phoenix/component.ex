defmodule Phoenix.Component do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import Phoenix.Component
      import Phoenix.Template, only: [embed_templates: 1, embed_templates: 2]
      import Phoenix.HTML
    end
  end

  defmacro attr(_name, _type, _opts \\ []), do: :ok
  defmacro slot(_name), do: :ok
  defmacro slot(_name, do: _block), do: :ok
  defmacro slot(_name, _opts), do: :ok
  defmacro slot(_name, _opts, do: _block), do: :ok

  defmacro sigil_H({:<<>>, meta, [string]}, _opts) when is_binary(string) do
    compiled = EEx.compile_string(string, line: meta[:line] || 1)

    quote do
      unquote(compiled)
    end
  end

  defmacro sigil_H(expr, _opts) do
    quote do
      unquote(expr)
    end
  end

  def used_input?(_field), do: false

  def assign(assigns, key, value) when is_atom(key) do
    Map.put(assigns, key, value)
  end

  def assign(assigns, key, value) when is_binary(key) do
    Map.put(assigns, String.to_existing_atom(key), value)
  end

  def assign(assigns, attrs) when is_map(attrs) or is_list(attrs) do
    Map.merge(assigns, Enum.into(attrs, %{}))
  end

  def assign_new(assigns, key, fun) when is_function(fun, 0) do
    if Map.has_key?(assigns, key) do
      assigns
    else
      Map.put(assigns, key, fun.())
    end
  end

  def render_slot(nil), do: ""
  def render_slot(slot) when is_binary(slot), do: slot
  def render_slot(slot) when is_function(slot, 1), do: slot.(%{})
  def live_title(assigns) do
    default = Map.get(assigns, :default, "App")
    suffix = Map.get(assigns, :suffix, "")
    page = Map.get(assigns, :page_title) || Map.get(assigns, "page_title")
    title = if page, do: "#{page}#{suffix}", else: "#{default}#{suffix}"
    "<title>#{title}</title>"
  end
end
