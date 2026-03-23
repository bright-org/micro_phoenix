defmodule AtomvmHttpServer.Router do
  alias AtomvmHttpServer.Request

  def route(%Request{method: :get, path: "/api/status"}) do
    body = ~s({"status":"ok","vm":"AtomVM","version":"0.1.0"})
    {:ok, 200, "application/json", body}
  end

  def route(%Request{method: :get, path: path}) do
    case AtomvmHttpServer.Static.get(path) do
      {:ok, content_type, body} -> {:ok, 200, content_type, body}
      {:error, :not_found} -> {:error, 404}
    end
  end

  def route(_request) do
    {:error, 405}
  end
end
