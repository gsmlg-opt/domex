defmodule Domex.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    [
      # Apply the existing Gaoxy adapter override across all umbrella dependencies.
      {:websock_adapter, "~> 0.13", hex: :gaoxy_websock_adapter, override: true}
    ]
  end

  defp aliases do
    [
      setup: ["cmd mix setup"],
      "assets.setup": ["do --app domex_web cmd mix npm.install"],
      "assets.build": ["duskmoon_bundler.build domex_web --tailwind --no-hash"],
      "assets.deploy": [
        "do --app domex_web cmd mix phx.digest.clean",
        "duskmoon_bundler.build domex_web --tailwind --no-hash",
        "do --app domex_web cmd mix phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
