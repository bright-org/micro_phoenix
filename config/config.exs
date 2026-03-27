import Config

config :atomvm_http_server,
  ecto_repos: [AtomvmHttpServer.Repo]

config :atomvm_http_server, AtomvmHttpServer.Repo,
  database: "priv/repo/dev.sqlite3",
  pool_size: 2

