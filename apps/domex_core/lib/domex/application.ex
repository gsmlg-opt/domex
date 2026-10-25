defmodule Domex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Domex.PubSub},
      {Registry, keys: :unique, name: Domex.Device.Registry},
      Domex.Device.DynamicSupervisor,
      Domex.ConfigStore,
      Domex.Discovery.Supervisor,
      {Domex.Sensor.Supervisor, Application.get_env(:domex_core, :sensor_mqtt, [])}
    ]

    opts = [strategy: :one_for_one, name: Domex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
