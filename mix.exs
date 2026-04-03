defmodule MicroPhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :micro_phoenix,
      version: "0.1.0",
      elixir: "~> 1.13",
      deps: deps(),
      atomvm: [
        start: MicroPhoenix
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MicroPhoenix.Application, []}
    ]
  end

  defp deps do
    [
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/"}
    ]
  end
end
