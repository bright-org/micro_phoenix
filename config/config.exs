import Config

config :micro_phoenix,
  port: 5000,
  listen_options: [{:inet_backend, :socket}]
