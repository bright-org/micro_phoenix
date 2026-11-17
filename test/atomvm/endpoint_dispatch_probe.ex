defmodule MicroPhoenix.EndpointDispatchProbe.Router do
  def call(%Plug.Conn{} = conn, []) do
    "GET" = conn.method
    "/status" = conn.request_path
    "x=1" = conn.query_string
    ["status"] = conn.path_info
    %{conn | status: 200, resp_body: "endpoint-ok"}
  end
end

defmodule MicroPhoenix.EndpointDispatchProbe do
  def start do
    send(self(), {:request, "GET /status?x=1 HTTP/1.1\r\nhost: localhost\r\n\r\n"})

    receive do
      {:request, request} ->
        {:ok, response} =
          Phoenix.Endpoint.Server.dispatch_router(
            request,
            MicroPhoenix.EndpointDispatchProbe.Router,
            static: []
          )

        true = :binary.match(response, "HTTP/1.1 200 OK") != :nomatch
        true = :binary.match(response, "endpoint-ok") != :nomatch
        :erlang.display(:endpoint_dispatch_ok)
    end

    :ok
  end
end
