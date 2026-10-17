defmodule Domex.Device.DynamicSupervisor do
  @moduledoc """
  DynamicSupervisor managing active Domex device sessions.
  """

  use DynamicSupervisor
  alias Domex.Device.Registry, as: DevRegistry
  alias Domex.Device.Session

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a device session under supervision.
  """
  def start_device(config) when is_map(config) do
    device_id =
      to_string(
        Map.get(config, :id) || Map.get(config, "id") ||
          "dev_#{:erlang.unique_integer([:positive])}"
      )

    case DevRegistry.whereis(device_id) do
      nil ->
        spec = {Session, Map.put(config, :id, device_id)}
        DynamicSupervisor.start_child(__MODULE__, spec)

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @doc """
  Stops and removes a device session.
  """
  def stop_device(device_id) do
    case DevRegistry.whereis(device_id) do
      pid when is_pid(pid) ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active device sessions currently supervised.
  """
  def which_devices do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn
      {_, pid, :worker, [Session]} when is_pid(pid) ->
        try do
          [Session.get_shadow(pid)]
        catch
          :exit, _ -> []
        end

      _ ->
        []
    end)
  end
end
