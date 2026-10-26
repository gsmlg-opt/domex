defmodule Domex.Sensor.BrokerTest do
  use ExUnit.Case, async: false

  alias Domex.Protocol.Sensor
  alias Domex.Sensor.{Broker, MQTT, Store}
  alias Tortoise311.Package

  setup context do
    parent = self()
    store = start_supervised!({Store, name: nil, broadcast: &send(parent, {:hub, &1})})

    options =
      Keyword.merge(
        [store: store, port: 0, ip: {127, 0, 0, 1}],
        Map.get(context, :broker_options, [])
      )

    broker = start_supervised!({Broker, options})
    {:ok, {_, port}} = ThousandIsland.listener_info(broker)
    %{store: store, broker: broker, port: port}
  end

  test "Tortoise311 connects, publishes telemetry, receives retained state and reconnects", %{
    store: store,
    broker: broker,
    port: port
  } do
    client_id = start_publisher(port)
    state_topic = Sensor.topic(Sensor.default_prefix(), "wire-test", :state)
    availability_topic = Sensor.topic(Sensor.default_prefix(), "wire-test", :availability)
    payload = snapshot(1)

    assert :ok =
             Tortoise311.publish_sync(client_id, availability_topic, "online",
               qos: 1,
               retain: true
             )

    assert_receive {:hub, {:sensor_updated, %{id: "wire-test", online?: true}}}, 5_000

    assert :ok = Tortoise311.publish_sync(client_id, state_topic, payload, qos: 0, retain: true)

    assert_receive {:hub, {:sensor_updated, %{status: "live", sample: %{"timestamp_ms" => 1}}}},
                   5_000

    assert {:ok, %{online?: true, name: "Wire Sensor"}} = Store.get("wire-test", store)
    {:ok, [publisher_connection]} = ThousandIsland.connection_pids(broker)

    parent = self()

    replica =
      start_supervised!({Store, name: nil, broadcast: &send(parent, {:replica, &1})},
        id: :replica
      )

    start_supervised!(
      {MQTT, host: "127.0.0.1", port: port, store: replica, client_id: "retained-subscriber"},
      id: :subscriber
    )

    assert_receive {:replica, {:sensor_updated, %{sample: %{"timestamp_ms" => 1}}}}, 5_000
    assert_receive {:replica, {:sensor_updated, %{online?: true}}}, 5_000

    assert {:ok, %{online?: true, sample: %{"timestamp_ms" => 1}}} =
             Store.get("wire-test", replica)

    assert :ok = MqttX.Server.disconnect(publisher_connection, 0x80)

    assert_receive {:hub, {:sensor_updated, %{online?: false}}}, 5_000
    assert_receive {:replica, {:sensor_updated, %{online?: false}}}, 5_000
    assert_receive {{Tortoise311, ^client_id}, :status, :up}, 5_000

    assert :ok =
             Tortoise311.publish_sync(client_id, availability_topic, "online",
               qos: 1,
               retain: true
             )

    assert_receive {:hub, {:sensor_updated, %{online?: true}}}, 5_000

    assert :ok =
             Tortoise311.publish_sync(client_id, state_topic, snapshot(2), qos: 0, retain: true)

    assert_receive {:replica, {:sensor_updated, %{sample: %{"timestamp_ms" => 2}}}}, 5_000
  end

  test "invalid sensor payloads and topics never reach the store", %{
    store: store,
    port: port
  } do
    client_id = start_publisher(port)

    for {topic, payload} <- [
          {"domex/sensors/broken/state", "{}"},
          {"domex/sensors/other/state", snapshot(1)},
          {"outside/wire-test/state", snapshot(1)}
        ] do
      assert :ok = Tortoise311.publish_sync(client_id, topic, payload, qos: 1, retain: true)
    end

    assert [] = Store.list(store)

    assert :ok =
             Tortoise311.publish_sync(client_id, "domex/sensors/wire-test/state", snapshot(1),
               qos: 1,
               retain: true
             )

    assert_receive {:hub, {:sensor_updated, %{id: "wire-test"}}}, 5_000

    start_supervised!(
      {MQTT, host: "127.0.0.1", port: port, store: store, client_id: "validation-subscriber"},
      id: :subscriber
    )

    assert_receive {:hub, {:sensor_updated, %{id: "wire-test"}}}, 5_000
    assert [%{id: "wire-test"}] = Store.list(store)
  end

  @tag broker_options: [user_name: "sensor", password: "test-password"]
  test "broker credentials reject anonymous and incorrect connections", %{port: port} do
    for credentials <- [[], [user_name: "sensor", password: "incorrect"]] do
      assert {:refused, :not_authorized} = connect_status(port, credentials)
    end

    assert :accepted = connect_status(port, user_name: "sensor", password: "test-password")
  end

  @tag broker_options: [prefix: "home/computers"]
  test "the configured topic prefix is used for ingestion", %{store: store, port: port} do
    client_id = start_publisher(port)

    assert :ok =
             Tortoise311.publish_sync(client_id, "home/computers/wire-test/state", snapshot(1),
               qos: 1
             )

    assert_receive {:hub, {:sensor_updated, %{id: "wire-test"}}}, 5_000
    assert {:ok, %{name: "Wire Sensor"}} = Store.get("wire-test", store)
  end

  defp start_publisher(port) do
    client_id = "broker-test-#{System.unique_integer([:positive])}"
    {:ok, _} = Tortoise311.Events.register(client_id, :status)

    start_supervised!(
      {Tortoise311.Connection,
       client_id: client_id,
       server: {Tortoise311.Transport.Tcp, host: "127.0.0.1", port: port},
       handler: {Tortoise311.Handler.Default, []},
       will: %Package.Publish{
         topic: "domex/sensors/wire-test/availability",
         payload: "offline",
         qos: 1,
         retain: true
       }}
    )

    assert_receive {{Tortoise311, ^client_id}, :status, :up}, 5_000
    client_id
  end

  defp connect_status(port, credentials) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 5_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    packet = struct!(Package.Connect, [client_id: "authentication-test"] ++ credentials)
    :ok = :gen_tcp.send(socket, Package.encode(packet))
    {:ok, connack} = :gen_tcp.recv(socket, 4, 5_000)
    :ok = :gen_tcp.close(socket)
    %Package.Connack{status: status} = Package.decode(connack)
    status
  end

  defp snapshot(timestamp) do
    Sensor.encode_state(
      %{
        sensor_id: "wire-test",
        name: "Wire Sensor",
        hostname: "wire.local",
        platform: "linux-arm64"
      },
      %{
        status: "live",
        error: "",
        sample: %{
          timestamp_ms: timestamp,
          cpu: %{total: 25.0},
          memory: %{percent: 50.0},
          cores: [],
          gpu: [],
          disk: %{},
          network: %{}
        }
      }
    )
  end
end
