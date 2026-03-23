defmodule AtomvmHttpServer.ApiHandler do
  @behaviour :httpd_api_handler

  @impl :httpd_api_handler
  def handle_api_request(:get, [], _http_request, _opts) do
    {:ok,
     %{
       status: "ok",
       vm: "AtomVM",
       version: "0.1.0"
     }}
  end

  def handle_api_request(_method, _path, _http_request, _opts) do
    {:error, :not_found}
  end
end
