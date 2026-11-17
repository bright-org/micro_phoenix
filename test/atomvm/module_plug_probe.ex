defmodule MicroPhoenix.ModulePlugProbe.MarkerPlug do
  def init(marker: marker), do: [marker: "initialized:" <> marker]

  def call(conn, marker: marker) do
    Plug.Conn.put_resp_header(conn, "x-module-plug", marker)
  end
end

defmodule MicroPhoenix.ModulePlugProbe.Controller do
  def index(conn, _params), do: Plug.Conn.send_resp(conn, 200, "ok")
end

defmodule MicroPhoenix.ModulePlugProbe.Router do
  use Phoenix.Router

  pipeline :browser do
    plug(MicroPhoenix.ModulePlugProbe.MarkerPlug, marker: "executed")
  end

  scope "/" do
    pipe_through(:browser)
    get("/module-plug", MicroPhoenix.ModulePlugProbe.Controller, :index)
  end
end

defmodule MicroPhoenix.ModulePlugProbe do
  def start do
    send(self(), {:request, "GET /module-plug HTTP/1.1\r\nhost: localhost\r\n\r\n"})

    receive do
      {:request, request} ->
        {:ok, response} =
          Phoenix.Endpoint.Server.dispatch_router(
            request,
            MicroPhoenix.ModulePlugProbe.Router,
            static: []
          )

        true = :binary.match(response, "HTTP/1.1 200 OK") != :nomatch
        true = :binary.match(response, "x-module-plug: initialized:executed") != :nomatch
        :erlang.display(:module_plug_atomvm_ok)
    end

    :ok
  end
end
