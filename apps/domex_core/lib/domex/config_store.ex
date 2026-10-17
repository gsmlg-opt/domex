defmodule Domex.ConfigStore do
  @moduledoc """
  Persistent configuration store for configured smart devices using Erlang DETS.

  Stores device credentials, addresses, and adapter assignments.
  Restores and starts all saved devices under `Domex.Device.DynamicSupervisor` on application start.
  """

  use GenServer
  require Logger

  alias Domex.Device.DynamicSupervisor, as: DevSupervisor

  @table :domex_devices

  defstruct [:table_name, :file_path]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns all configured device records.
  """
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc """
  Retrieves a single configured device by ID.
  """
  def get(device_id) when is_binary(device_id) or is_atom(device_id) do
    GenServer.call(__MODULE__, {:get, to_string(device_id)})
  end

  @doc """
  Persists or updates a device record.
  """
  def put(config) when is_map(config) do
    GenServer.call(__MODULE__, {:put, config})
  end

  @doc """
  Deletes a device record by ID.
  """
  def delete(device_id) when is_binary(device_id) or is_atom(device_id) do
    GenServer.call(__MODULE__, {:delete, to_string(device_id)})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    file_path =
      Keyword.get(opts, :file_path) ||
        Application.get_env(:domex, :config_store_file) ||
        default_dets_file()

    dir = Path.dirname(file_path)
    File.mkdir_p!(dir)

    charlist_path = String.to_charlist(file_path)

    case :dets.open_file(@table, file: charlist_path, type: :set) do
      {:ok, table} ->
        state = %__MODULE__{
          table_name: table,
          file_path: file_path
        }

        auto_start? = Keyword.get(opts, :auto_start, true)

        if auto_start? do
          {:ok, state, {:continue, :restore_devices}}
        else
          {:ok, state}
        end

      {:error, reason} ->
        Logger.error(
          "[Domex.ConfigStore] Failed to open DETS table at #{file_path}: #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:restore_devices, state) do
    devices = read_all(state.table_name)
    Logger.info("[Domex.ConfigStore] Restoring #{length(devices)} saved devices")

    Enum.each(devices, fn config ->
      case DevSupervisor.start_device(config) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "[Domex.ConfigStore] Failed to restore device #{inspect(config[:id])}: #{inspect(reason)}"
          )
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    devices = read_all(state.table_name)
    {:reply, devices, state}
  end

  def handle_call({:get, device_id}, _from, state) do
    case :dets.lookup(state.table_name, device_id) do
      [{^device_id, config}] ->
        {:reply, {:ok, config}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:put, config}, _from, state) do
    device_id =
      to_string(
        Map.get(config, :id) || Map.get(config, "id") ||
          "dev_#{:erlang.unique_integer([:positive])}"
      )

    normalized = normalize_config(config, device_id)

    case :dets.insert(state.table_name, {device_id, normalized}) do
      :ok ->
        :dets.sync(state.table_name)
        {:reply, {:ok, normalized}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, device_id}, _from, state) do
    :dets.delete(state.table_name, device_id)
    :dets.sync(state.table_name)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.table_name do
      :dets.close(state.table_name)
    end

    :ok
  end

  # Helpers

  defp read_all(table) do
    :dets.foldl(
      fn {_id, config}, acc -> [config | acc] end,
      [],
      table
    )
  end

  defp normalize_config(config, device_id) do
    %{
      id: device_id,
      name: Map.get(config, :name) || Map.get(config, "name") || device_id,
      type: Map.get(config, :type) || Map.get(config, "type") || :unknown,
      adapter: Map.get(config, :adapter) || Map.get(config, "adapter"),
      host: Map.get(config, :host) || Map.get(config, "host"),
      port: Map.get(config, :port) || Map.get(config, "port"),
      token: Map.get(config, :token) || Map.get(config, "token"),
      metadata: Map.get(config, :metadata) || Map.get(config, "metadata") || %{}
    }
  end

  defp default_dets_file do
    case :code.priv_dir(:domex_core) do
      {:error, :bad_name} ->
        Path.join([File.cwd!(), "apps", "domex_core", "priv", "data", "devices.dets"])

      priv ->
        Path.join([priv, "data", "devices.dets"])
    end
  end
end
