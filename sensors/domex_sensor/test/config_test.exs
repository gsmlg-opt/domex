defmodule DomexSensor.ConfigTest do
  use ExUnit.Case, async: true
  alias DomexSensor.Config

  test "has standalone defaults without Phoenix secrets or endpoint configuration" do
    options = Config.from_env(%{})
    assert options[:host] == "localhost"
    assert options[:port] == 1883
    assert options[:prefix] == "domex/sensors"
    assert options[:publish_interval_ms] == 1_000
    assert Domex.Protocol.Sensor.valid_id?(options[:identity].sensor_id)
  end

  test "reads broker settings and sensor identity" do
    options =
      Config.from_env(%{
        "DOMEX_SENSOR_ID" => "desk",
        "DOMEX_SENSOR_NAME" => "Desk Mac",
        "DOMEX_MQTT_HOST" => "broker.local",
        "DOMEX_MQTT_PORT" => "8883",
        "DOMEX_MQTT_TLS" => "true"
      })

    assert options[:host] == "broker.local"
    assert options[:port] == 8883
    assert options[:tls]
    assert options[:identity].sensor_id == "desk"
    assert options[:identity].name == "Desk Mac"
  end

  test "invalid identifiers and numeric settings fail early" do
    for env <- [
          %{"DOMEX_SENSOR_ID" => "desk/+"},
          %{"DOMEX_MQTT_PREFIX" => "domex/#"},
          %{"DOMEX_MQTT_PORT" => "0"},
          %{"DOMEX_MQTT_PORT" => "1883junk"},
          %{"DOMEX_SENSOR_PUBLISH_INTERVAL_MS" => "-1"},
          %{"DOMEX_MQTT_TLS" => "maybe"}
        ] do
      assert_raise ArgumentError, fn -> Config.from_env(env) end
    end
  end
end
