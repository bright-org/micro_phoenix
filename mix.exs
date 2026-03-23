defmodule AtomvmHttpServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :atomvm_http_server,
      version: "0.1.0",
      elixir: "~> 1.13",
      deps: deps(),
      atomvm: [
        start: AtomvmHttpServer
      ]
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/"}
    ]
  end
end
