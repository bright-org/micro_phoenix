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
    file = __CALLER__.file
    line = meta[:line] || 1
    compiled = Phoenix.Template.compile_heex_source(string, "#{file}:#{line}")

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
    Map.put(assigns, :erlang.binary_to_existing_atom(key, :utf8), value)
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

  def assign_new(assigns, key, fun) when is_function(fun, 1) do
    if Map.has_key?(assigns, key) do
      assigns
    else
      Map.put(assigns, key, fun.(assigns))
    end
  end

  # Match Phoenix.Component: empty slots return nil so `:if={msg = render_slot(...) || ...}` works.
  def render_slot(nil), do: nil
  def render_slot([]), do: nil
  def render_slot(""), do: nil
  def render_slot(slot) when is_binary(slot), do: slot
  def render_slot(slot) when is_function(slot, 1), do: blank_to_nil(slot.(%{}))
  def render_slot(%{inner_block: fun}) when is_function(fun), do: blank_to_nil(fun.(%{}))
  def render_slot([%{inner_block: fun} | _]) when is_function(fun), do: blank_to_nil(fun.(%{}))
  def render_slot(_), do: nil

  def render_slot(nil, _arg), do: nil
  def render_slot([], _), do: nil
  def render_slot("", _), do: nil
  def render_slot(slot, _arg) when is_binary(slot), do: slot
  def render_slot(slot, arg) when is_function(slot, 1), do: blank_to_nil(slot.(arg))
  def render_slot(%{inner_block: fun}, arg) when is_function(fun), do: blank_to_nil(fun.(arg))
  def render_slot([%{inner_block: fun} | _], arg) when is_function(fun), do: blank_to_nil(fun.(arg))
  def render_slot(_, _), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil({:safe, data}) do
    case iodata_empty?(data) do
      true -> nil
      false -> {:safe, data}
    end
  end
  defp blank_to_nil(other), do: other

  defp iodata_empty?(data) when data in ["", []], do: true
  defp iodata_empty?(data) when is_list(data), do: Enum.all?(data, &iodata_empty?/1)
  defp iodata_empty?(_), do: false

  def to_form(data, opts \\ [])

  def to_form(%Phoenix.HTML.Form{} = form, _opts), do: form

  def to_form(data, opts) do
    Phoenix.HTML.FormData.to_form(data, opts)
  end

  def live_title(assigns) do
    default = Map.get(assigns, :default, "App")
    suffix = Map.get(assigns, :suffix, "")
    page = Map.get(assigns, :page_title) || Map.get(assigns, "page_title")
    title = if page, do: "#{page}#{suffix}", else: "#{default}#{suffix}"

    {:safe, ["<title>", Phoenix.HTML.Safe.to_iodata(title), "</title>"]}
  end

  def link(assigns) do
    href = assigns[:href] || assigns[:navigate] || assigns[:patch] || "#"
    class = Map.get(assigns, :class)
    method = Map.get(assigns, :method) || Map.get(assigns[:rest] || %{}, :method)
    rest = Map.get(assigns, :rest, %{})
    method = if method, do: method |> to_string() |> Phoenix.Binary.downcase_ascii()

    class_attr =
      if class do
        [" class=\"", Phoenix.Template.__class_list__(List.wrap(class)), "\""]
      else
        ""
      end

    confirm = rest[:data_confirm] || assigns[:data_confirm]

    confirm_attr =
      if confirm do
        [" data-confirm=\"", Phoenix.HTML.html_escape(to_string(confirm)), "\""]
      else
        ""
      end

    body = Map.get(assigns, :inner_block) |> render_slot()

    if method && method != "get" do
      # No Phoenix JS is available on AtomVM, so data-method links must work as plain HTML.
      {:safe,
       [
         "<form action=\"",
         Phoenix.HTML.html_escape(to_string(href)),
         "\" method=\"post\" style=\"display:inline\">",
         "<input type=\"hidden\" name=\"_method\" value=\"",
         Phoenix.HTML.html_escape(method),
         "\">",
         "<input type=\"hidden\" name=\"_csrf_token\" value=\"",
         Phoenix.HTML.html_escape(csrf_token()),
         "\">",
         "<button type=\"submit\"",
         class_attr,
         confirm_attr,
         " style=\"background:none;border:0;padding:0;color:inherit;font:inherit;cursor:pointer\">",
         body,
         "</button>",
         "</form>"
       ]}
    else
      {:safe,
       [
         "<a href=\"",
         Phoenix.HTML.html_escape(to_string(href)),
         "\"",
         class_attr,
         confirm_attr,
         ">",
         body,
         "</a>"
       ]}
    end
  end

  def form(assigns) do
    form = to_form(assigns[:for], form_opts(assigns))
    action = assigns[:action] || "#"
    method = assigns[:method] || form.options[:method] || "post"
    method = method |> to_string() |> Phoenix.Binary.downcase_ascii()

    {browser_method, method_override} =
      cond do
        method in ["get", "post"] -> {method, nil}
        true -> {"post", method}
      end

    body = render_slot(Map.get(assigns, :inner_block), form)

    hidden =
      [
        if(method_override,
          do: [
            "<input type=\"hidden\" name=\"_method\" value=\"",
            Phoenix.HTML.html_escape(method_override),
            "\">"
          ]
        ),
        if(browser_method != "get",
          do: [
            "<input type=\"hidden\" name=\"_csrf_token\" value=\"",
            Phoenix.HTML.html_escape(csrf_token()),
            "\">"
          ]
        ),
        Enum.map(form.hidden || [], fn {k, v} ->
          [
            "<input type=\"hidden\" name=\"",
            Phoenix.HTML.html_escape("#{form.name}[#{k}]"),
            "\" value=\"",
            Phoenix.HTML.html_escape(to_string(v)),
            "\">"
          ]
        end)
      ]
      |> Enum.reject(&is_nil/1)

    {:safe,
     [
       "<form action=\"",
       Phoenix.HTML.html_escape(to_string(action)),
       "\" method=\"",
       browser_method,
       "\">",
       hidden,
       body,
       "</form>"
     ]}
  end

  defp form_opts(assigns) do
    []
    |> maybe_put_opt(:as, assigns[:as])
    |> maybe_put_opt(:id, assigns[:id])
    |> maybe_put_opt(:method, assigns[:method])
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp csrf_token, do: "atomvm"
end
