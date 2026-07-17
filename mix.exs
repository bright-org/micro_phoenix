defmodule MicroPhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :micro_phoenix,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:plug, "~> 1.14"},
      {:plug_crypto, "~> 2.0"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.2"},
      # AtomVM-oriented fork (app name remains :phoenix_html)
      {:phoenix_html,
       git: "https://github.com/bright-org/micro_phoenix_html.git", branch: "main"},
      {:exatomvm, git: "https://github.com/atomvm/ExAtomVM/"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
