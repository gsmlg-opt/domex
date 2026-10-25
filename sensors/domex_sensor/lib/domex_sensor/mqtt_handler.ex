defmodule DomexSensor.MQTTHandler do
  @moduledoc false
  use Tortoise311.Handler

  @impl true
  def init(options), do: {:ok, Keyword.fetch!(options, :publisher)}

  @impl true
  def connection(status, publisher) do
    DomexSensor.Publisher.connection(status, publisher)
    {:ok, publisher}
  end
end
