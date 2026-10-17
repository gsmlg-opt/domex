defmodule DomexCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :domex_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Domex.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp deps do
    [
      {:domex_protocol, in_umbrella: true},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
