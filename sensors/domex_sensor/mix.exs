defmodule DomexSensor.MixProject do
  use Mix.Project

  def project do
    [
      app: :domex_sensor,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [
        precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
      ],
      releases: [domex_sensor: [steps: [&build_probe/1, :assemble]]]
    ]
  end

  def cli, do: [preferred_envs: [precommit: :test]]

  def application do
    [mod: {DomexSensor.Application, []}, extra_applications: [:logger, :ssl]]
  end

  defp deps do
    [
      {:domex_protocol, path: "../../apps/domex_protocol"},
      {:jason, "~> 1.2"},
      {:tortoise311, "~> 0.12.1"}
    ]
  end

  defp build_probe(release) do
    DomexSensor.Probe.build!()
    release
  end
end
