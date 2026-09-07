defmodule MicroPhoenix.Controller do
  alias MicroPhoenix.Conn

  defmacro __using__(_opts) do
    quote do
      import MicroPhoenix.Controller
    end
  end

  def render(%Conn{} = conn, template, assigns \\ []) when is_atom(template) do
    controller = Map.fetch!(conn.private, :controller)
    view = view_module(conn, controller)
    assigns = build_assigns(conn, assigns)
    html = apply(view, template, [assigns])
    html(conn, html)
  end

  def html(%Conn{} = conn, body) when is_binary(body) do
    %{
      conn
      | halted: true,
        status: 200,
        resp_content_type: "text/html",
        resp_body: body
    }
  end

  def json(%Conn{} = conn, data) do
    body = encode_json(data)

    %{
      conn
      | halted: true,
        status: 200,
        resp_content_type: "application/json",
        resp_body: body
    }
  end

  def redirect(%Conn{} = conn, opts) do
    path = Keyword.fetch!(opts, :to)

    %{
      conn
      | halted: true,
        status: 302,
        resp_content_type: "text/html",
        resp_body: "",
        resp_headers: [{"location", path} | conn.resp_headers]
    }
  end

  def put_flash(%Conn{} = conn, kind, message) do
    %{conn | flash: Map.put(conn.flash, kind, message)}
  end

  def put_status(%Conn{} = conn, status) do
    %{conn | status: status}
  end

  def assign(%Conn{} = conn, key, value) do
    %{conn | assigns: Map.put(conn.assigns, key, value)}
  end

  def put_view(%Conn{} = conn, view) do
    %{conn | private: Map.put(conn.private, :view_module, view)}
  end

  defp build_assigns(%Conn{} = conn, assigns) do
    assigns
    |> Enum.into(%{})
    |> Map.merge(conn.assigns)
    |> Map.put(:flash, conn.flash)
  end

  defp view_module(%Conn{private: private}, controller) do
    Map.get(private, :view_module) || default_view_module(controller)
  end

  defp default_view_module(controller) do
    parts = Module.split(controller)
    base = parts |> List.last() |> String.replace_suffix("Controller", "HTML")
    Module.concat(Enum.drop(parts, -1) ++ [base])
  end

  defp encode_json(data) when is_map(data) do
    "{" <>
      Enum.map_join(data, ",", fn {k, v} ->
        ~s("#{k}":#{encode_json_value(v)})
      end) <> "}"
  end

  defp encode_json(data), do: encode_json_value(data)

  defp encode_json_value(value) when is_binary(value), do: ~s("#{value}")
  defp encode_json_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_json_value(value) when is_boolean(value), do: to_string(value)
  defp encode_json_value(value) when is_atom(value), do: ~s("#{value}")
  defp encode_json_value(value), do: ~s("#{inspect(value)}")
end
