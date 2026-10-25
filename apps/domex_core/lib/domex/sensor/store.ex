defmodule Domex.Sensor.Store do
  @moduledoc "Bounded sensor snapshots received over MQTT, with availability and stale detection."
  use GenServer

  @topic "sensors:all"

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(is_nil(name), do: [], else: [name: name]))
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Domex.PubSub, @topic)
  def list(server \\ __MODULE__), do: GenServer.call(server, :list)
  def get(id, server \\ __MODULE__), do: GenServer.call(server, {:get, id})
  def ingest(id, event, server \\ __MODULE__), do: GenServer.cast(server, {:ingest, id, event})
  def disconnected(server \\ __MODULE__), do: GenServer.cast(server, :disconnected)

  @impl true
  def init(options) do
    state = %{
      sensors: %{},
      stale_after_ms: Keyword.get(options, :stale_after_ms, 60_000),
      max_sensors: Keyword.get(options, :max_sensors, 1_000),
      sweep_ms: Keyword.get(options, :sweep_ms, 5_000),
      broadcast: Keyword.get(options, :broadcast, &broadcast/1)
    }

    Process.send_after(self(), :expire, state.sweep_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:list, _from, state),
    do: {:reply, state.sensors |> Map.values() |> Enum.sort_by(& &1.name), state}

  def handle_call({:get, id}, _from, state), do: {:reply, Map.fetch(state.sensors, id), state}

  @impl true
  def handle_cast({:ingest, id, event}, state) do
    if Map.has_key?(state.sensors, id) or map_size(state.sensors) < state.max_sensors do
      sensor = Map.get(state.sensors, id, empty_sensor(id)) |> apply_event(event)
      state.broadcast.({:sensor_updated, sensor})
      {:noreply, put_in(state, [:sensors, id], sensor)}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:disconnected, state) do
    sensors = Map.new(state.sensors, fn {id, sensor} -> {id, %{sensor | available?: false}} end)
    {:noreply, mark_offline(%{state | sensors: sensors}, fn _sensor -> true end)}
  end

  @impl true
  def handle_info(:expire, state) do
    now = System.monotonic_time(:millisecond)
    state = mark_offline(state, &(now - &1.last_seen > state.stale_after_ms))
    Process.send_after(self(), :expire, state.sweep_ms)
    {:noreply, state}
  end

  defp empty_sensor(id) do
    %{
      id: id,
      name: id,
      hostname: "",
      platform: "",
      online?: false,
      available?: false,
      status: "warming",
      error: "",
      sample: nil,
      history: [],
      updated_at: nil,
      last_seen: System.monotonic_time(:millisecond)
    }
  end

  defp apply_event(sensor, {:availability, online?}),
    do: %{sensor | online?: online?, available?: online?}

  defp apply_event(sensor, {:state, data}) do
    sample = data["sample"]

    history =
      if is_map(sample) and sample != sensor.sample,
        do: Enum.take(sensor.history ++ [sample], -60),
        else: sensor.history

    %{
      sensor
      | name: data["name"],
        online?: sensor.available?,
        hostname: data["hostname"],
        platform: data["platform"],
        status: data["status"],
        error: data["error"],
        sample: sample,
        history: history,
        updated_at: DateTime.utc_now(),
        last_seen: System.monotonic_time(:millisecond)
    }
  end

  defp mark_offline(state, predicate) do
    sensors =
      Map.new(state.sensors, fn {id, sensor} ->
        if sensor.online? and predicate.(sensor) do
          offline = %{sensor | online?: false}
          state.broadcast.({:sensor_updated, offline})
          {id, offline}
        else
          {id, sensor}
        end
      end)

    %{state | sensors: sensors}
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Domex.PubSub, @topic, event)
end
