defmodule AtomvmHttpServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_http_server,
      version: "0.1.0",
      elixir: "~> 1.13",
      deps: deps(),
      aliases: [
        setup: ["ecto.create", "ecto.migrate"]
      ],
      atomvm: [
        start: AtomvmHttpServer
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AtomvmHttpServer.Application, []}
    ]
  end

  defp deps do
    [
      {:micro_scaffold_example, git: "git@github.com:bright-org/micro_scaffold_example.git"},
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/"},
      {:ecto_sqlite3, "~> 0.21"}
    ]
  end
end
