defmodule Domex.Device.Shadow do
  @moduledoc """
  Pure immutable shadow state reducer for smart devices.

  Maintains device representation, online status, unified capability attributes
  (power, brightness, color temp, rgb, climate temperature, mode, fan speed),
  and arbitrary adapter-specific properties.
  """

  @type device_type :: :light | :climate | :switch | :sensor | :unknown

  defstruct [
    :id,
    :name,
    :type,
    :adapter,
    :host,
    :port,
    :token,
    online?: false,
    power: false,
    brightness: nil,
    color_temp: nil,
    rgb: nil,
    ac_temp: nil,
    ac_target_temp: nil,
    ac_mode: nil,
    ac_fan_speed: nil,
    ac_swing_vertical: false,
    ac_swing_horizontal: false,
    properties: %{},
    updated_at: nil
  ]

  @doc """
  Creates a new Shadow struct initialized with default config values.
  """
  @spec new(map()) :: %__MODULE__{}
  def new(attrs \\ %{}) do
    id =
      Map.get(attrs, :id) || Map.get(attrs, "id") || "dev_#{:erlang.unique_integer([:positive])}"

    name = Map.get(attrs, :name) || Map.get(attrs, "name") || id
    type = infer_type(attrs)
    adapter = Map.get(attrs, :adapter) || Map.get(attrs, "adapter")
    host = Map.get(attrs, :host) || Map.get(attrs, "host")
    port = Map.get(attrs, :port) || Map.get(attrs, "port")
    token = Map.get(attrs, :token) || Map.get(attrs, "token")

    %__MODULE__{
      id: to_string(id),
      name: to_string(name),
      type: type,
      adapter: adapter,
      host: host,
      port: port,
      token: token,
      online?: Map.get(attrs, :online?, false),
      power: Map.get(attrs, :power, false),
      brightness: Map.get(attrs, :brightness),
      color_temp: Map.get(attrs, :color_temp),
      rgb: Map.get(attrs, :rgb),
      ac_temp: Map.get(attrs, :ac_temp),
      ac_target_temp: Map.get(attrs, :ac_target_temp),
      ac_mode: Map.get(attrs, :ac_mode),
      ac_fan_speed: Map.get(attrs, :ac_fan_speed),
      ac_swing_vertical: Map.get(attrs, :ac_swing_vertical, false),
      ac_swing_horizontal: Map.get(attrs, :ac_swing_horizontal, false),
      properties: Map.get(attrs, :properties, %{}),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Applies an event to the shadow state, producing an updated shadow struct.
  Pure and deterministic.
  """
  @spec apply_event(%__MODULE__{}, term()) :: %__MODULE__{}
  def apply_event(%__MODULE__{} = shadow, {:online, online?}) when is_boolean(online?) do
    %{shadow | online?: online?, updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, {:disconnected, _reason}) do
    %{shadow | online?: false, updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, {:connected, _meta}) do
    %{shadow | online?: true, updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, {:props, props}) when is_map(props) do
    new_props = Map.merge(shadow.properties, props)

    shadow =
      Enum.reduce(props, shadow, fn {key, val}, acc ->
        apply_prop(acc, to_string(key), val)
      end)

    %{shadow | properties: new_props, online?: true, updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, {:state, state_map}) when is_map(state_map) do
    shadow =
      shadow
      |> update_if_present(:power, state_map[:power])
      |> update_if_present(:ac_target_temp, state_map[:target_temp])
      |> update_if_present(:ac_temp, state_map[:indoor_temp])
      |> update_if_present(:ac_mode, state_map[:mode])
      |> update_if_present(:ac_fan_speed, state_map[:fan_speed])
      |> update_if_present(:ac_swing_vertical, state_map[:swing_vertical])
      |> update_if_present(:ac_swing_horizontal, state_map[:swing_horizontal])

    new_props = Map.merge(shadow.properties, state_map)
    %{shadow | properties: new_props, online?: true, updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, {:set, changes}) when is_map(changes) do
    updated =
      Enum.reduce(changes, shadow, fn {key, val}, acc ->
        atom_key =
          case to_atom_key(key) do
            :mode -> :ac_mode
            :target_temp -> :ac_target_temp
            :fan_speed -> :ac_fan_speed
            :swing_vertical -> :ac_swing_vertical
            :swing_horizontal -> :ac_swing_horizontal
            other -> other
          end

        if Map.has_key?(acc, atom_key) and atom_key not in [:id, :adapter, :updated_at] do
          Map.put(acc, atom_key, val)
        else
          %{acc | properties: Map.put(acc.properties, to_string(key), val)}
        end
      end)

    %{updated | updated_at: DateTime.utc_now()}
  end

  def apply_event(%__MODULE__{} = shadow, _unhandled) do
    shadow
  end

  defp apply_prop(shadow, "power", val) when val in ["on", true, 1], do: %{shadow | power: true}

  defp apply_prop(shadow, "power", val) when val in ["off", false, 0],
    do: %{shadow | power: false}

  defp apply_prop(shadow, "bright", val) do
    case parse_int(val) do
      nil -> shadow
      n -> %{shadow | brightness: n}
    end
  end

  defp apply_prop(shadow, "brightness", val) do
    case parse_int(val) do
      nil -> shadow
      n -> %{shadow | brightness: n}
    end
  end

  defp apply_prop(shadow, "ct", val) do
    case parse_int(val) do
      nil -> shadow
      n -> %{shadow | color_temp: n}
    end
  end

  defp apply_prop(shadow, "color_temp", val) do
    case parse_int(val) do
      nil -> shadow
      n -> %{shadow | color_temp: n}
    end
  end

  defp apply_prop(shadow, "rgb", val) do
    case parse_int(val) do
      nil -> shadow
      n -> %{shadow | rgb: n}
    end
  end

  defp apply_prop(shadow, _key, _val), do: shadow

  defp update_if_present(shadow, _key, nil), do: shadow
  defp update_if_present(shadow, key, val), do: Map.put(shadow, key, val)

  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_int(_), do: nil

  defp to_atom_key(key) when is_atom(key), do: key

  defp to_atom_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> :unknown_key
    end
  end

  defp infer_type(attrs) do
    type_attr = Map.get(attrs, :type) || Map.get(attrs, "type")

    case type_attr do
      t when t in [:light, :climate, :switch, :sensor] ->
        t

      "light" ->
        :light

      "climate" ->
        :climate

      "switch" ->
        :switch

      "sensor" ->
        :sensor

      _ ->
        adapter = to_string(Map.get(attrs, :adapter) || Map.get(attrs, "adapter") || "")

        cond do
          String.contains?(adapter, "Yeelight") -> :light
          String.contains?(adapter, "Midea") -> :climate
          String.contains?(adapter, "Miio") -> :switch
          true -> :unknown
        end
    end
  end
end
