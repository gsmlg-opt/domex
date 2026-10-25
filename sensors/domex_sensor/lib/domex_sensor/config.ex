defmodule DomexSensor.Config do
  @moduledoc "Validates standalone sensor configuration without requiring hub configuration."

  alias Domex.Protocol.Sensor

  def from_env(env) do
    {:ok, hostname} = :inet.gethostname()
    hostname = to_string(hostname)
    default_id = hostname |> String.replace(~r/[^a-zA-Z0-9_.-]/, "-") |> String.slice(0, 120)
    id = Map.get(env, "DOMEX_SENSOR_ID", "sensor-" <> default_id)
    prefix = Map.get(env, "DOMEX_MQTT_PREFIX", Sensor.default_prefix())

    unless Sensor.valid_id?(id),
      do:
        raise(
          ArgumentError,
          "DOMEX_SENSOR_ID must be a valid MQTT topic identifier (1-128 letters, digits, dots, hyphens or underscores)"
        )

    unless Sensor.valid_prefix?(prefix),
      do:
        raise(
          ArgumentError,
          "DOMEX_MQTT_PREFIX must contain nonempty topic levels without MQTT wildcards"
        )

    [
      host: nonempty!(env, "DOMEX_MQTT_HOST", "localhost"),
      port: integer!(env, "DOMEX_MQTT_PORT", 1883, 1..65_535),
      tls: boolean!(env, "DOMEX_MQTT_TLS", false),
      cacertfile: env["DOMEX_MQTT_CA_CERT"],
      user_name: env["DOMEX_MQTT_USERNAME"],
      password: env["DOMEX_MQTT_PASSWORD"],
      prefix: prefix,
      client_id: "domex-sensor-" <> id,
      publish_interval_ms: integer!(env, "DOMEX_SENSOR_PUBLISH_INTERVAL_MS", 1_000, 250..30_000),
      identity: %{
        sensor_id: id,
        name: nonempty!(env, "DOMEX_SENSOR_NAME", hostname),
        hostname: hostname,
        platform: platform()
      }
    ]
  end

  defp platform do
    {_, os} = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string() |> String.split("-") |> hd()
    "#{os}-#{arch}"
  end

  defp integer!(env, key, default, range) do
    case Integer.parse(Map.get(env, key, to_string(default))) do
      {value, ""} ->
        if value in range,
          do: value,
          else: raise(ArgumentError, "#{key} is outside its supported range")

      _ ->
        raise ArgumentError, "#{key} must be an integer"
    end
  end

  defp boolean!(env, key, default) do
    case Map.get(env, key, to_string(default)) do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      _ -> raise ArgumentError, "#{key} must be true or false"
    end
  end

  defp nonempty!(env, key, default) do
    value = Map.get(env, key, default)

    if is_binary(value) and byte_size(value) in 1..255,
      do: value,
      else: raise(ArgumentError, "#{key} must contain 1-255 bytes")
  end
end
