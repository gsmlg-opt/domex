defmodule DomexSensor.PublisherTest do
  use ExUnit.Case, async: true
  alias DomexSensor.{Config, Publisher}

  setup do
    parent = self()

    publish = fn _client, topic, payload, options ->
      send(parent, {:published, topic, payload, options})
      :ok
    end

    options =
      Config.from_env(%{"DOMEX_SENSOR_ID" => "desk"})
      |> Keyword.merge(name: nil, publish: publish, publish_interval_ms: 60_000)

    %{publisher: start_supervised!({Publisher, options}), options: options}
  end

  defp snapshot(error), do: %{status: "warming", error: error, sample: nil, history: []}

  test "reconnect publishes only the newest offline snapshot and retained availability", %{
    publisher: publisher
  } do
    Publisher.report(snapshot("old"), publisher)
    Publisher.report(snapshot("new"), publisher)
    _ = :sys.get_state(publisher)
    refute_received {:published, _, _, _}
    Publisher.connection(:up, publisher)
    assert_receive {:published, "domex/sensors/desk/availability", "online", options}
    assert options[:qos] == 1
    assert options[:retain]
    assert_receive {:published, "domex/sensors/desk/state", payload, options}
    assert Jason.decode!(payload)["error"] == "new"
    assert options[:qos] == 0
    Publisher.connection(:down, publisher)
    send(publisher, :publish)
    _ = :sys.get_state(publisher)
    refute_received {:published, _, _, _}
  end

  test "graceful shutdown publishes offline and stops telemetry", %{publisher: publisher} do
    Publisher.connection(:up, publisher)
    assert_receive {:published, _, "online", _}
    assert :ok = Publisher.offline(publisher)
    assert_receive {:published, "domex/sensors/desk/availability", "offline", _}
    Publisher.report(snapshot("ignored"), publisher)
    send(publisher, :publish)
    _ = :sys.get_state(publisher)
    refute_received {:published, _, _, _}
  end

  test "connection uses a retained QoS 1 offline last will", %{options: options} do
    connection = Publisher.connection_options(options)

    assert %{topic: "domex/sensors/desk/availability", payload: "offline", retain: true, qos: 1} =
             connection[:will]
  end
end
