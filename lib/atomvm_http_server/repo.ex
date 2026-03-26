defmodule AtomvmHttpServer.Repo do
  use Ecto.Repo,
    otp_app: :atomvm_http_server,
    adapter: Ecto.Adapters.SQLite3
end

