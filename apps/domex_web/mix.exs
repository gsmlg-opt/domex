defmodule DomexWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :domex_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers() ++ [:hologram],
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {DomexWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:domex_core, in_umbrella: true},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2"},
      {:lazy_html, ">= 0.1.0"},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:phoenix_duskmoon, "~> 10.0"},
      {:duskmoon_hologram, "~> 10.0"},
      {:duskmoon_bundler_runtime, "~> 10.0"},
      {:duskmoon_bundler, "~> 10.0", runtime: Mix.env() != :prod},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3"},
      {:gaoxy_http, "~> 0.13"},
      # Phoenix requires Gaoxy's WebSockAdapter distribution for WebSocket upgrades.
      {:websock_adapter, "~> 0.13", hex: :gaoxy_websock_adapter, override: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["npm.install"],
      "assets.build": ["duskmoon_bundler.build domex_web --tailwind --no-hash"],
      "assets.deploy": [
        "phx.digest.clean",
        "duskmoon_bundler.build domex_web --tailwind --no-hash",
        "phx.digest"
      ]
    ]
  end
end
