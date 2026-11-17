defmodule Phoenix.Router.ModulePlugTest do
  use ExUnit.Case, async: true

  defmodule MarkerPlug do
    def init(marker: marker), do: [marker: "initialized:" <> marker]

    def call(conn, marker: marker) do
      Plug.Conn.put_resp_header(conn, "x-module-plug", marker)
    end
  end

  defmodule StopPlug do
    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> Plug.Conn.resp(403, "blocked")
      |> Plug.Conn.halt()
    end
  end

  defmodule LaterPlug do
    def init(opts), do: opts
    def call(conn, _opts), do: Plug.Conn.put_resp_header(conn, "x-later", "ran")
  end

  defmodule HaltController do
    def index(conn, _params), do: Plug.Conn.resp(conn, 200, "controller")
  end

  defmodule HaltRouter do
    use Phoenix.Router

    pipeline :browser do
      plug(Phoenix.Router.ModulePlugTest.StopPlug)
      plug(Phoenix.Router.ModulePlugTest.LaterPlug)
    end

    scope "/" do
      pipe_through(:browser)
      get("/halt", Phoenix.Router.ModulePlugTest.HaltController, :index)
    end
  end

  defmodule ParameterPlug do
    def init(opts), do: opts

    def call(conn, _opts) do
      Plug.Conn.put_resp_header(
        conn,
        "x-parameter",
        conn.path_params["id"] <> ":" <> conn.params["id"] <> ":" <> conn.params["source"]
      )
    end
  end

  defmodule ParameterController do
    def show(conn, _params), do: Plug.Conn.resp(conn, 200, "ok")
  end

  defmodule ParameterRouter do
    use Phoenix.Router

    pipeline :browser do
      plug(Phoenix.Router.ModulePlugTest.ParameterPlug)
    end

    scope "/" do
      pipe_through(:browser)
      get("/items/:id", Phoenix.Router.ModulePlugTest.ParameterController, :show)
    end
  end

  defmodule MissingRouter do
    use Phoenix.Router

    pipeline :browser do
      plug(Phoenix.Router.ModulePlugTest.MissingPlug)
    end

    scope "/" do
      pipe_through(:browser)
      get("/missing-plug", Phoenix.Router.ModulePlugTest.ParameterController, :show)
    end
  end

  defmodule Controller do
    def index(conn, _params), do: Plug.Conn.send_resp(conn, 200, "ok")
  end

  defmodule Router do
    use Phoenix.Router

    pipeline :browser do
      plug(Phoenix.Router.ModulePlugTest.MarkerPlug, marker: "executed")
    end

    scope "/" do
      pipe_through(:browser)
      get("/module-plug", Phoenix.Router.ModulePlugTest.Controller, :index)
    end
  end

  test "a module plug in a router pipeline runs before the controller" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch_router(
               "GET /module-plug HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Router,
               static: []
             )

    assert response =~ "x-module-plug: initialized:executed"
    assert response =~ "HTTP/1.1 200 OK"
  end

  test "a halted pipeline skips later plugs and the controller" do
    conn = HaltRouter.call(%Plug.Conn{method: "GET", request_path: "/halt", params: %{}}, [])

    assert conn.halted
    assert conn.status == 403
    assert conn.resp_body == "blocked"
    assert Plug.Conn.get_resp_header(conn, "x-later") == []
  end

  test "route params are available to pipeline plugs" do
    conn = %Plug.Conn{
      method: "GET",
      request_path: "/items/42",
      params: %{"source" => "body", "id" => "old"}
    }

    response = ParameterRouter.call(conn, [])

    assert response.status == 200
    assert Plug.Conn.get_resp_header(response, "x-parameter") == ["42:42:body"]
  end

  test "an unresolved pipeline plug fails instead of dispatching" do
    conn = %Plug.Conn{method: "GET", request_path: "/missing-plug", params: %{}}

    assert_raise ArgumentError, ~r/router plug not found/, fn ->
      MissingRouter.call(conn, [])
    end
  end
end
