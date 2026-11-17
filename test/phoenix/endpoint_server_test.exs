defmodule Phoenix.Endpoint.ServerTest do
  use ExUnit.Case, async: true

  defmodule Router do
    def call(conn, _opts), do: %{conn | status: 201, resp_body: "created"}
  end

  test "encodes the reason phrase for a created response" do
    assert {:ok, response} =
             Phoenix.Endpoint.Server.dispatch_router(
               "POST /items HTTP/1.1\r\nhost: localhost\r\n\r\n",
               Router,
               static: []
             )

    assert response =~ "HTTP/1.1 201 Created\r\n"
  end
end
