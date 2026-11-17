defmodule MicroPhoenix.EndpointRouteProbe.Controller do
  def show(conn, %{"id" => id}) do
    %{conn | status: 200, resp_body: "item-" <> id}
  end

  def create(conn, %{"item" => %{"name" => name}}) do
    %{conn | status: 201, resp_body: "created-" <> name}
  end
end

defmodule MicroPhoenix.EndpointRouteProbe.Router do
  use Phoenix.Router

  get("/items/:id", MicroPhoenix.EndpointRouteProbe.Controller, :show)
  post("/items", MicroPhoenix.EndpointRouteProbe.Controller, :create)
end

defmodule MicroPhoenix.EndpointRouteProbe do
  def start do
    {:ok, response} =
      Phoenix.Endpoint.Server.dispatch_router(
        "GET /items/42 HTTP/1.1\r\nhost: localhost\r\n\r\n",
        MicroPhoenix.EndpointRouteProbe.Router,
        static: []
      )

    true = :binary.match(response, "HTTP/1.1 200 OK") != :nomatch
    true = :binary.match(response, "item-42") != :nomatch

    {:ok, missing_response} =
      Phoenix.Endpoint.Server.dispatch_router(
        "GET /missing HTTP/1.1\r\nhost: localhost\r\n\r\n",
        MicroPhoenix.EndpointRouteProbe.Router,
        static: []
      )

    true = :binary.match(missing_response, "HTTP/1.1 404 Not Found") != :nomatch

    {:ok, post_response} =
      Phoenix.Endpoint.Server.dispatch_router(
        "POST /items HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/x-www-form-urlencoded\r\ncontent-length: 20\r\n\r\nitem[name]=hello+you",
        MicroPhoenix.EndpointRouteProbe.Router,
        static: []
      )

    true = :binary.match(post_response, "HTTP/1.1 201 Created") != :nomatch
    true = :binary.match(post_response, "created-hello you") != :nomatch
    :erlang.display(:endpoint_route_ok)
    :ok
  end
end
