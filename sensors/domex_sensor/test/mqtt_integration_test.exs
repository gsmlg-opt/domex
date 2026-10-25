defmodule DomexSensor.MQTTIntegrationTest do
  use ExUnit.Case, async: true
  alias DomexSensor.{Config, Publisher}
  alias Tortoise311.Package

  test "real MQTT connection sends retained availability, telemetry and latest readings after reconnect" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, {_, port}} = :inet.sockname(listener)
    parent = self()
    start_supervised!({Task, fn -> accept(listener, parent) end})

    options =
      Config.from_env(%{
        "DOMEX_SENSOR_ID" => "wire-test",
        "DOMEX_MQTT_HOST" => "127.0.0.1",
        "DOMEX_MQTT_PORT" => to_string(port)
      })
      |> Keyword.merge(name: __MODULE__.Publisher, publish_interval_ms: 60_000)

    publisher = start_supervised!({Publisher, options})
    Publisher.report(%{status: "warming", error: "first", sample: nil}, publisher)
    start_supervised!({Tortoise311.Connection, Publisher.connection_options(options)})

    assert_receive {:connect, socket, %Package.Connect{will: will}}, 5000
    assert %{payload: "offline", retain: true, qos: 1} = will

    assert_receive {:publish,
                    %Package.Publish{
                      topic: "domex/sensors/wire-test/availability",
                      payload: "online",
                      qos: 1,
                      retain: true
                    }},
                   5000

    assert_receive {:publish,
                    %Package.Publish{
                      topic: "domex/sensors/wire-test/state",
                      payload: payload,
                      qos: 0,
                      retain: true
                    }},
                   5000

    assert Jason.decode!(payload)["error"] == "first"

    :ok = :gen_tcp.close(socket)
    Publisher.report(%{status: "warming", error: "second", sample: nil}, publisher)
    Publisher.report(%{status: "warming", error: "latest", sample: nil}, publisher)
    assert_receive {:connect, _socket, %Package.Connect{}}, 5000
    assert_receive {:publish, %Package.Publish{payload: "online"}}, 5000

    assert_receive {:publish,
                    %Package.Publish{topic: "domex/sensors/wire-test/state", payload: latest}},
                   5000

    assert Jason.decode!(latest)["error"] == "latest"

    assert :ok = Publisher.offline(publisher)
    assert_receive {:publish, %Package.Publish{payload: "offline"}}, 5000
  end

  defp accept(listener, parent) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, connect} = receive_packet(socket)
        send(parent, {:connect, socket, connect})
        :ok = :gen_tcp.send(socket, <<0x20, 2, 0, 0>>)
        receive_publishes(socket, parent)
        accept(listener, parent)

      {:error, :closed} ->
        :ok
    end
  end

  defp receive_publishes(socket, parent) do
    case receive_packet(socket) do
      {:ok, %Package.Publish{} = publish} ->
        if publish.qos == 1,
          do:
            :gen_tcp.send(socket, Package.encode(%Package.Puback{identifier: publish.identifier}))

        send(parent, {:publish, publish})
        receive_publishes(socket, parent)

      {:ok, %Package.Pingreq{}} ->
        :gen_tcp.send(socket, <<0xD0, 0>>)
        receive_publishes(socket, parent)

      {:error, :closed} ->
        :ok
    end
  end

  defp receive_packet(socket) do
    with {:ok, header} <- :gen_tcp.recv(socket, 1, 5000),
         {:ok, length_bytes, length} <- receive_length(socket, <<>>, 0, 1),
         {:ok, body} <-
           if(length == 0, do: {:ok, <<>>}, else: :gen_tcp.recv(socket, length, 5000)) do
      {:ok, Package.decode(header <> length_bytes <> body)}
    end
  end

  defp receive_length(socket, bytes, length, multiplier) do
    with {:ok, <<more::1, digit::7>> = byte} <- :gen_tcp.recv(socket, 1, 5000) do
      length = length + digit * multiplier

      if more == 0,
        do: {:ok, bytes <> byte, length},
        else: receive_length(socket, bytes <> byte, length, multiplier * 128)
    end
  end
end
