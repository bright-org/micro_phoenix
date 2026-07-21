defmodule Phoenix.Controller do
  @moduledoc false

  defmacro __using__(opts) do
    formats = Keyword.get(opts, :formats, [:html])

    quote bind_quoted: [formats: formats] do
      import Phoenix.Controller
      @phoenix_controller_formats formats
    end
  end

  def accepts(conn, _accepted) do
    Plug.Conn.put_resp_content_type(conn, "text/html")
  end

  def fetch_session(conn, _opts \\ []) do
    conn
  end

  def fetch_live_flash(conn, _opts \\ []) do
    Plug.Conn.assign(conn, :flash, %{})
  end

  def put_root_layout(conn, opts) do
    Plug.Conn.put_private(conn, :phoenix_root_layout, Keyword.fetch!(opts, :html))
  end

  def put_layout(conn, opts) do
    Plug.Conn.put_private(conn, :phoenix_layout, Keyword.fetch!(opts, :html))
  end

  def protect_from_forgery(conn, _opts \\ []) do
    # Avoid Plug.CSRFProtection (Process dict / crypto not available on AtomVM).
    Plug.Conn.assign(conn, :csrf_token, "atomvm")
  end

  def put_secure_browser_headers(conn, _opts \\ []) do
    conn
    |> Plug.Conn.put_resp_header("x-frame-options", "SAMEORIGIN")
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
  end

  def render(conn, template, assigns \\ [])

  def render(conn, template, assigns) when is_atom(template) do
    conn = prepare_assigns(conn, assigns)
    controller = conn.private[:phoenix_controller] || infer_controller(conn)
    view = view_module(conn, controller)
    html = apply(view, template, [Map.put(conn.assigns, :conn, conn)])
    html = render_layout(conn, html) |> to_resp_body()
    status = conn.status || 200

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(status, html)
  end

  def render(conn, template, assigns) when is_binary(template) do
    render(conn, String.to_existing_atom(template), assigns)
  end

  def render(conn, %{format: format} = template, assigns) do
    render(conn, template_to_atom(template, format), assigns)
  end

  def render(conn, %{}, assigns), do: render(conn, :show, assigns)

  def html(conn, body) when is_binary(body) do
    status = conn.status || 200
    conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(status, body)
  end

  def json(conn, data) do
    body = Phoenix.json_library().encode!(data)
    status = conn.status || 200
    conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(status, body)
  end

  def redirect(conn, opts) do
    to = Keyword.fetch!(opts, :to)
    conn |> Plug.Conn.put_resp_header("location", to) |> Plug.Conn.send_resp(302, "") |> Plug.Conn.halt()
  end

  def put_flash(conn, kind, message) do
    flash = Map.put(conn.assigns[:flash] || %{}, kind, message)
    Plug.Conn.assign(conn, :flash, flash)
  end

  def put_view(conn, module) do
    Plug.Conn.put_private(conn, :phoenix_view, module)
  end

  def put_status(conn, status), do: %{conn | status: status}

  def get_csrf_token, do: "atomvm"

  def view_module(conn, controller \\ nil) do
    conn.private[:phoenix_view] || default_view_module(controller || conn.private[:phoenix_controller])
  end

  def view_template(conn, template \\ nil)
  def view_template(conn, nil), do: conn.private[:phoenix_template]
  def view_template(_conn, template), do: template

  def status_message_from_template("404.html"), do: "Not Found"
  def status_message_from_template("500.html"), do: "Internal Server Error"
  def status_message_from_template(template), do: template

  defp prepare_assigns(conn, assigns) do
    # Avoid Map.put_new/3 (missing on some AtomVM Elixir builds).
    merged =
      assigns
      |> Enum.into(%{})
      |> Map.merge(conn.assigns)

    flash = Map.get(merged, :flash) || %{}
    %{conn | assigns: Map.put(merged, :flash, flash)}
  end

  defp infer_controller(conn) do
    conn.private[:phoenix_controller]
  end

  defp default_view_module(nil), do: nil

  defp default_view_module(controller) when is_atom(controller) do
    # Avoid Module.split/1 and String.replace_suffix/2 (missing on AtomVM).
    parts =
      controller
      |> Atom.to_string()
      |> strip_elixir_prefix()
      |> Phoenix.Binary.split(".")

    base = parts |> List.last() |> controller_to_html()
    module_from_parts(drop_last(parts) ++ [base])
  end

  defp strip_elixir_prefix(<<"Elixir.", rest::binary>>), do: rest
  defp strip_elixir_prefix(other), do: other

  defp controller_to_html(name) when is_binary(name) do
    suffix = "Controller"
    size = byte_size(name)
    suffix_size = byte_size(suffix)

    if size >= suffix_size and binary_part(name, size - suffix_size, suffix_size) == suffix do
      binary_part(name, 0, size - suffix_size) <> "HTML"
    else
      name <> "HTML"
    end
  end

  defp drop_last([]), do: []
  defp drop_last([_]), do: []
  defp drop_last([h | t]), do: [h | drop_last(t)]

  defp module_from_parts(parts) when is_list(parts) do
    ("Elixir." <> Enum.join(parts, "."))
    |> :erlang.binary_to_atom(:utf8)
  end

  defp render_layout(conn, inner) do
    case conn.private[:phoenix_root_layout] do
      {layout_mod, layout_tpl} ->
        layout_mod = resolve_layout_module(layout_mod)
        flash = conn.assigns[:flash] || %{}

        apply(layout_mod, layout_tpl, [
          %{inner_content: inner, flash: flash, conn: conn}
        ])

      _ ->
        inner
    end
  end

  defp resolve_layout_module({:__aliases__, _, parts}), do: module_from_parts(Enum.map(parts, &to_string/1))
  defp resolve_layout_module(mod) when is_atom(mod), do: mod

  defp to_resp_body({:safe, html}), do: flatten_iodata(html)
  defp to_resp_body(html) when is_binary(html), do: html
  defp to_resp_body(html) when is_list(html), do: flatten_iodata(html)

  defp to_resp_body(other) do
    other
    |> Phoenix.HTML.Safe.to_iodata()
    |> flatten_iodata()
  rescue
    _ -> to_string(other)
  end

  defp flatten_iodata(data) do
    data
    |> do_flatten([])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  # Walk iodata recursively. Prefer [h|t] over Enum.reduce so improper
  # lists from Phoenix.HTML (e.g. [bin | "&#39;"]) are handled.
  defp do_flatten({:safe, data}, acc), do: do_flatten(data, acc)
  defp do_flatten([], acc), do: acc
  defp do_flatten([head | tail], acc), do: do_flatten(tail, do_flatten(head, acc))
  defp do_flatten(bin, acc) when is_binary(bin), do: [bin | acc]
  defp do_flatten(int, acc) when is_integer(int) and int >= 0 and int <= 255, do: [int | acc]

  defp do_flatten(other, acc) do
    iodata =
      try do
        Phoenix.HTML.Safe.to_iodata(other)
      rescue
        _ -> to_string(other)
      end

    do_flatten(iodata, acc)
  end

  defp template_to_atom(%{root: root, path: path}, _format) do
    path
    |> String.trim_leading("/")
    |> String.replace("/", "_")
    |> then(&String.replace_suffix(root, "", &1))
    |> String.to_atom()
  rescue
    _ -> :show
  end
end
