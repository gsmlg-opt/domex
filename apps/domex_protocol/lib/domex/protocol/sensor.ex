defmodule Domex.Protocol.Sensor do
  @moduledoc """
  Version 1 MQTT contract shared by the hub and standalone sensors.

  Retained JSON snapshots use `<prefix>/<sensor_id>/state`; retained availability
  uses `<prefix>/<sensor_id>/availability` with `online` or `offline` payloads.
  """

  @default_prefix "domex/sensors"
  @max_payload_bytes 1_048_576

  def default_prefix, do: @default_prefix

  def valid_id?(id) when is_binary(id),
    do: Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/, id)

  def valid_id?(_), do: false

  def valid_prefix?(prefix) when is_binary(prefix) do
    byte_size(prefix) in 1..512 and
      Enum.all?(String.split(prefix, "/"), fn level ->
        level != "" and not String.contains?(level, ["+", "#", <<0>>])
      end)
  end

  def valid_prefix?(_), do: false

  def topic(prefix, sensor_id, kind) when kind in [:state, :availability],
    do: "#{prefix}/#{sensor_id}/#{kind}"

  def subscriptions(prefix),
    do: [{"#{prefix}/+/state", 0}, {"#{prefix}/+/availability", 1}]

  def encode_state(identity, snapshot) do
    identity
    |> Map.take([:sensor_id, :name, :hostname, :platform])
    |> Map.merge(Map.take(snapshot, [:status, :error, :sample]))
    |> Map.put(:schema_version, 1)
    |> Jason.encode!()
  end

  def decode(topic, payload, prefix \\ @default_prefix)

  def decode(topic, payload, prefix)
      when is_binary(topic) and is_binary(payload) and byte_size(payload) <= @max_payload_bytes do
    with true <- String.starts_with?(topic, prefix <> "/"),
         [id, kind] <- topic |> String.replace_prefix(prefix <> "/", "") |> String.split("/"),
         true <- valid_id?(id) do
      decode_payload(id, kind, payload)
    else
      _ -> {:error, :invalid_topic}
    end
  end

  def decode(_, _, _), do: {:error, :invalid_payload}

  defp decode_payload(id, "availability", "online"), do: {:ok, id, {:availability, true}}
  defp decode_payload(id, "availability", "offline"), do: {:ok, id, {:availability, false}}

  defp decode_payload(id, "state", payload) do
    with {:ok, %{"schema_version" => 1, "sensor_id" => ^id} = state} <- Jason.decode(payload),
         true <- valid_state?(state) do
      {:ok, id, {:state, state}}
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp decode_payload(_, _, _), do: {:error, :invalid_payload}

  defp valid_state?(state) do
    Enum.all?(["name", "hostname", "platform"], fn key ->
      is_binary(state[key]) and byte_size(state[key]) in 1..255
    end) and state["status"] in ["warming", "live", "error"] and
      is_binary(state["error"]) and byte_size(state["error"]) <= 4_096 and
      (is_nil(state["sample"]) or valid_sample?(state["sample"]))
  end

  defp valid_sample?(%{"timestamp_ms" => timestamp, "cpu" => cpu, "memory" => memory} = sample) do
    is_integer(timestamp) and timestamp >= 0 and is_map(cpu) and is_map(memory) and
      Enum.all?(
        ["cores", "gpu"],
        &(is_list(sample[&1]) and Enum.all?(sample[&1], fn x -> is_map(x) end))
      ) and
      Enum.all?(["disk", "network"], &is_map(sample[&1]))
  end

  defp valid_sample?(_), do: false
end
