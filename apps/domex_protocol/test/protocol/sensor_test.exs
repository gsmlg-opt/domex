defmodule Domex.Protocol.SensorTest do
  use ExUnit.Case, async: true
  alias Domex.Protocol.Sensor

  @identity %{
    sensor_id: "desk-mac",
    name: "Desk Mac",
    hostname: "desk.local",
    platform: "darwin-arm64"
  }
  @snapshot %{status: "warming", error: "", sample: nil, history: [], samples: 0}

  test "state round trip excludes local history and sample counts" do
    payload = Sensor.encode_state(@identity, @snapshot)

    assert {:ok, "desk-mac", {:state, state}} =
             Sensor.decode("domex/sensors/desk-mac/state", payload)

    assert state["schema_version"] == 1
    assert state["name"] == "Desk Mac"
    refute Map.has_key?(state, "history")
    refute Map.has_key?(state, "samples")
  end

  test "topic and payload identifiers must agree and unknown versions are rejected" do
    payload = Sensor.encode_state(@identity, @snapshot)
    assert {:error, :invalid_state} = Sensor.decode("domex/sensors/other/state", payload)
    unknown = payload |> Jason.decode!() |> Map.put("schema_version", 2) |> Jason.encode!()
    assert {:error, :invalid_state} = Sensor.decode("domex/sensors/desk-mac/state", unknown)
  end

  test "availability and custom prefixes have exact topic matching" do
    assert {:ok, "desk-mac", {:availability, true}} =
             Sensor.decode("home/status/desk-mac/availability", "online", "home/status")

    assert {:ok, "desk-mac", {:availability, false}} =
             Sensor.decode("domex/sensors/desk-mac/availability", "offline")

    assert {:error, :invalid_topic} =
             Sensor.decode("other/domex/sensors/desk-mac/availability", "online")

    assert {:error, :invalid_topic} = Sensor.decode("domex/sensors/desk-mac/state/extra", "{}")

    assert {:error, :invalid_payload} =
             Sensor.decode("domex/sensors/desk-mac/availability", "yes")
  end

  test "malformed, oversized and incomplete snapshots are rejected without raising" do
    topic = "domex/sensors/desk-mac/state"

    for payload <- ["not JSON", "[]", "null", String.duplicate("x", 1_048_577)] do
      assert {:error, _} = Sensor.decode(topic, payload)
    end

    for sample <- [%{}, %{"timestamp_ms" => 123, "cpu" => %{}, "memory" => %{}}] do
      assert {:error, :invalid_state} =
               Sensor.decode(topic, Sensor.encode_state(@identity, %{@snapshot | sample: sample}))
    end
  end

  test "device identifiers and topic prefixes cannot contain wildcard levels" do
    for id <- ["+", "#", "desk/mac", "", String.duplicate("a", 129)],
        do: refute(Sensor.valid_id?(id))

    for prefix <- ["", "domex/+", "domex/#", "/domex", "domex/", "domex//sensors"],
        do: refute(Sensor.valid_prefix?(prefix))

    assert Sensor.valid_id?("mac-mini_01.local")
    assert Sensor.valid_prefix?("home/domex/sensors")
  end
end
