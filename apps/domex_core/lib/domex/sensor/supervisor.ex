defmodule Domex.Sensor.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    children = [{Domex.Sensor.Store, []}]

    children =
      if Keyword.get(options, :enabled, false),
        do: children ++ [{Domex.Sensor.MQTT, options}],
        else: children

    # Reconnect after a cache restart so retained availability is restored too.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
