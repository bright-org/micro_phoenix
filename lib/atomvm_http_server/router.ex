defmodule AtomvmHttpServer.Router do
  alias AtomvmHttpServer.Request

  def route(%Request{method: :get, path: "/api/status"}) do
    body = ~s({"status":"ok","vm":"AtomVM","version":"0.1.0"})
    {:ok, 200, "application/json", body}
  end

  def route(%Request{method: :get} = req) do
    case get(req) do
      {:ok, status, content_type, body} ->
        {:ok, status, content_type, body}

      :not_found ->
        AtomvmHttpServer.Static.get_error_page(404)

    end
  end

  def route(_request) do
    AtomvmHttpServer.Static.get_error_page(405)
  end

  def get(conn) when conn.path in ["/", "/index.html"] do
    AtomvmHttpServerWeb.Controller.index(conn)
  end

  def get(_conn), do: :not_found
end
