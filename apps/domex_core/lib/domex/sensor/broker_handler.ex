defmodule Domex.Sensor.BrokerHandler do
  @moduledoc false
  use MqttX.Server

  alias Domex.Protocol.Sensor
  alias Domex.Sensor.Store

  @impl true
  def init(options), do: options |> Map.new() |> Map.put(:client_id, nil)

  @impl true
  def handle_connect(client_id, credentials, state) do
    if is_nil(state.user_name) or
         (credentials.username == state.user_name and credentials.password == state.password) do
      {:ok, %{state | client_id: client_id}}
    else
      {:error, 0x87, state}
    end
  end

  @impl true
  def handle_publish(topic, payload, options, state) do
    topic = MqttX.Topic.flatten(topic)

    case Sensor.decode(topic, payload, state.prefix) do
      {:ok, id, event} ->
        Store.ingest(id, event, state.store)
        MqttX.Server.deliver(topic, payload, Map.put(options, :publisher, state.client_id))
        {:ok, state}

      {:error, _reason} ->
        {:error, :topic_name_invalid, state}
    end
  end

  @impl true
  def handle_subscribe(topics, state) do
    grants =
      Enum.map(topics, fn topic ->
        if String.starts_with?(MqttX.Topic.flatten(topic.topic), state.prefix <> "/"),
          do: topic.qos,
          else: 0x87
      end)

    {:ok, grants, state}
  end

  @impl true
  def handle_disconnect(_reason, _state), do: :ok
end
