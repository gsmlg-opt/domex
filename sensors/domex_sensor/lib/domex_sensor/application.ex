defmodule DomexSensor.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    options = Application.get_env(:domex_sensor, :options, [])

    children =
      if Application.get_env(:domex_sensor, :enabled, true) do
        [
          {DomexSensor.Publisher, options},
          {Tortoise311.Connection, DomexSensor.Publisher.connection_options(options)},
          {DomexSensor.Monitor, broadcaster: &DomexSensor.Publisher.report/1}
        ]
      else
        []
      end

    Supervisor.start_link(children, strategy: :rest_for_one, name: DomexSensor.Supervisor)
  end

  @impl true
  def prep_stop(state) do
    if Process.whereis(DomexSensor.Publisher), do: DomexSensor.Publisher.offline()
    state
  end
end
