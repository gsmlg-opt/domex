defmodule Domex.Sensor.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    children = [{Domex.Sensor.Store, []}]

    children =
      case Keyword.get(options, :mode, :disabled) do
        :embedded -> children ++ [{Domex.Sensor.Broker, options}]
        :external -> children ++ [{Domex.Sensor.MQTT, options}]
        :disabled -> children
      end

    # Restart MQTT connections after the sensor store is replaced.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
