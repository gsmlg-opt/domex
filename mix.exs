defmodule Domex.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["cmd mix setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind domex_web", "esbuild domex_web"],
      "assets.deploy": [
        "tailwind domex_web --minify",
        "esbuild domex_web --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
