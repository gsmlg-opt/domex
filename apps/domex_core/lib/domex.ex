defmodule Domex do
  @moduledoc """
  Public facade API for the Domex smart home platform.

  Provides device lifecycle management, real-time shadow access,
  discovery triggers, and command dispatch.
  """

  alias Domex.ConfigStore
  alias Domex.Device.DynamicSupervisor, as: DevSupervisor
  alias Domex.Device.Registry, as: DevRegistry
  alias Domex.Device.Session
  alias Domex.Device.Shadow
  alias Domex.Discovery.MideaListener
  alias Domex.Discovery.MiioProbe

  @doc """
  Lists all devices, combining configured records with their live Shadow state.
  """
  @spec list_devices() :: list(%Shadow{})
  def list_devices do
    # Fetch all configured records from store
    configs =
      try do
        ConfigStore.all()
      catch
        :exit, _ -> []
      end

    config_map = Map.new(configs, fn c -> {to_string(c[:id] || c["id"]), c} end)

    # Fetch all active supervised sessions
    active_shadows =
      try do
        DevSupervisor.which_devices()
      catch
        :exit, _ -> []
      end

    active_map = Map.new(active_shadows, fn s -> {s.id, s} end)

    # Merge: active shadow takes precedence for online state/props,
    # fall back to stored configuration if session is offline/stopped.
    all_ids = (Map.keys(config_map) ++ Map.keys(active_map)) |> Enum.uniq()

    Enum.map(all_ids, fn id ->
      case Map.fetch(active_map, id) do
        {:ok, shadow} ->
          shadow

        :error ->
          cfg = Map.get(config_map, id, %{})
          Shadow.new(cfg)
      end
    end)
  end

  @doc """
  Retrieves the live Shadow struct for a single device by ID.
  """
  @spec get_device(String.t()) :: {:ok, %Shadow{}} | {:error, :not_found}
  def get_device(device_id) when is_binary(device_id) do
    case DevRegistry.whereis(device_id) do
      pid when is_pid(pid) ->
        try do
          {:ok, Session.get_shadow(pid)}
        catch
          :exit, _ ->
            fallback_from_config(device_id)
        end

      nil ->
        fallback_from_config(device_id)
    end
  end

  @doc """
  Registers and starts a new device.
  Persists configuration in ConfigStore and starts a Session under DynamicSupervisor.
  """
  @spec add_device(map()) :: {:ok, %Shadow{}} | {:error, term()}
  def add_device(attrs) when is_map(attrs) do
    case ConfigStore.put(attrs) do
      {:ok, saved_config} ->
        case DevSupervisor.start_device(saved_config) do
          {:ok, pid} ->
            {:ok, Session.get_shadow(pid)}

          {:error, {:already_started, pid}} ->
            {:ok, Session.get_shadow(pid)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops and deletes a device.
  """
  @spec remove_device(String.t()) :: :ok | {:error, term()}
  def remove_device(device_id) when is_binary(device_id) do
    _ = DevSupervisor.stop_device(device_id)
    ConfigStore.delete(device_id)
    :ok
  end

  @doc """
  Turns a device on or off with optimistic state update.
  """
  @spec set_power(String.t(), boolean()) :: {:ok, term()} | {:error, term()}
  def set_power(device_id, power?) when is_binary(device_id) and is_boolean(power?) do
    # Optimistic local UI update
    Session.set_shadow(device_id, %{power: power?})
    Session.command(device_id, :set_power, [power?])
  end

  @doc """
  Toggles the power state of a device.
  """
  @spec toggle(String.t()) :: {:ok, term()} | {:error, term()}
  def toggle(device_id) when is_binary(device_id) do
    case get_device(device_id) do
      {:ok, shadow} ->
        set_power(device_id, !shadow.power)

      error ->
        error
    end
  end

  @doc """
  Sets the brightness of a light (1..100).
  """
  @spec set_brightness(String.t(), integer()) :: {:ok, term()} | {:error, term()}
  def set_brightness(device_id, level) when is_binary(device_id) and is_integer(level) do
    clamped = max(1, min(100, level))
    Session.set_shadow(device_id, %{brightness: clamped, power: true})
    Session.command(device_id, :set_brightness, [clamped])
  end

  @doc """
  Sets the color temperature of a light in Kelvin (1700..6500).
  """
  @spec set_color_temp(String.t(), integer()) :: {:ok, term()} | {:error, term()}
  def set_color_temp(device_id, kelvin) when is_binary(device_id) and is_integer(kelvin) do
    clamped = max(1700, min(6500, kelvin))
    Session.set_shadow(device_id, %{color_temp: clamped, power: true})
    Session.command(device_id, :set_color_temp, [clamped])
  end

  @doc """
  Sets RGB integer color of a light (0..16777215).
  """
  @spec set_rgb(String.t(), integer()) :: {:ok, term()} | {:error, term()}
  def set_rgb(device_id, rgb) when is_binary(device_id) and is_integer(rgb) do
    Session.set_shadow(device_id, %{rgb: rgb, power: true})
    Session.command(device_id, :set_rgb, [rgb])
  end

  @doc """
  Sends climate / AC control settings (target_temp, mode, fan_speed, swing).
  """
  @spec set_ac(String.t(), map()) :: {:ok, term()} | {:error, term()}
  def set_ac(device_id, attrs) when is_binary(device_id) and is_map(attrs) do
    # Map into shadow attributes
    shadow_changes =
      attrs
      |> Map.take([:power, :mode, :fan_speed, :swing_vertical, :swing_horizontal])
      |> then(fn m ->
        case Map.get(attrs, :target_temp) do
          nil -> m
          t -> Map.put(m, :ac_target_temp, t)
        end
      end)

    Session.set_shadow(device_id, shadow_changes)
    Session.command(device_id, :control, attrs)
  end

  @doc """
  Triggers a network sweep for smart devices.
  """
  def discover do
    MiioProbe.sweep()
    MideaListener.probe()
    :ok
  end

  defp fallback_from_config(device_id) do
    case ConfigStore.get(device_id) do
      {:ok, config} ->
        {:ok, Shadow.new(config)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
