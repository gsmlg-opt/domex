defmodule Domex.Sensor.MQTTTest do
  use ExUnit.Case, async: true
  alias Domex.Sensor.{MQTT, Store}

  test "handler decodes status, rejects invalid data and marks devices offline on connection loss" do
    parent = self()
    store = start_supervised!({Store, name: nil, broadcast: &send(parent, &1)})
    state = %{prefix: "domex/sensors", store: store}

    assert {:ok, ^state} =
             MQTT.handle_message(["domex", "sensors", "mac", "availability"], "online", state)

    assert_receive {:sensor_updated, %{id: "mac", online?: true}}

    assert {:ok, ^state} =
             MQTT.handle_message(["domex", "sensors", "broken", "state"], "{}", state)

    assert [%{id: "mac"}] = Store.list(store)
    assert {:ok, ^state} = MQTT.connection(:down, state)
    assert_receive {:sensor_updated, %{id: "mac", online?: false}}
  end
end
