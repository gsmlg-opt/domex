defmodule DomexSensor.Monitor do
  @moduledoc "Owns one persistent native probe, keeps 60 samples, and broadcasts monitor snapshots."

  use GenServer

  alias DomexSensor.{Linux, Metrics, Platform, Probe}

  @empty %{status: "warming", error: "", sample: nil, history: [], samples: 0}
  @max_line_bytes 1_048_576

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(is_nil(name), do: [], else: [name: name]))
  end

  @doc "Reads the named process's ETS cache without waiting for native compilation."
  def snapshot(server \\ __MODULE__)

  def snapshot(server) when is_atom(server) do
    case :ets.whereis(server) do
      :undefined -> @empty
      table -> read_cache(table)
    end
  end

  def snapshot(server), do: GenServer.call(server, :snapshot)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    name = Keyword.get(opts, :name, __MODULE__)
    table_opts = [:set, :protected, read_concurrency: true]

    table_opts =
      if is_atom(name) and name != nil, do: [:named_table | table_opts], else: table_opts

    cache_name = if is_atom(name) and name != nil, do: name, else: __MODULE__
    cache = :ets.new(cache_name, table_opts)
    :ets.insert(cache, {:snapshot, @empty})
    native_dir = Probe.native_dir()

    platform =
      Platform.resolve(
        Keyword.get(opts, :os_type, :os.type()),
        Keyword.get(opts, :architecture, :erlang.system_info(:system_architecture))
      )

    {default_binary, default_source, default_sources} =
      case platform do
        {:ok, %{kind: :proc}} ->
          {nil, nil, []}

        {:ok, target} ->
          {Path.join([native_dir, "bin", target.id, "system_probe"]),
           Path.join(native_dir, target.source),
           Enum.map(target.sources, &Path.join(native_dir, &1))}

        {:error, _} ->
          {nil, nil, []}
      end

    sources =
      if Keyword.has_key?(opts, :source_path),
        do: [Keyword.fetch!(opts, :source_path)],
        else: default_sources

    minimum = max(Keyword.get(opts, :restart_min_ms, 500), 1)

    state = %{
      opts: Keyword.put_new(opts, :skip_build, System.get_env("RELEASE_ROOT") != nil),
      sample_timer: nil,
      sample_interval_ms: Keyword.get(opts, :sample_interval_ms, 1_000),
      linux_options: Keyword.get(opts, :linux_options, []),
      platform: platform,
      cache: cache,
      value: @empty,
      previous: nil,
      port: nil,
      buffer: "",
      retry_ref: nil,
      retry_ms: minimum,
      minimum: minimum,
      maximum: max(Keyword.get(opts, :restart_max_ms, 30_000), minimum),
      probe_path: Keyword.get(opts, :probe_path, default_binary),
      source_path: Keyword.get(opts, :source_path, default_source),
      sources: sources,
      broadcaster: Keyword.get(opts, :broadcaster, &broadcast/1)
    }

    {:ok, state, {:continue, :start_probe}}
  end

  @impl true
  def handle_continue(:start_probe, state), do: {:noreply, start_probe(state)}

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.value, state}

  @impl true
  def handle_info(:sample, state), do: {:noreply, collect_linux(%{state | sample_timer: nil})}

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    buffer = state.buffer <> chunk

    if byte_size(buffer) > @max_line_bytes do
      {:noreply, fail(state, "System probe output exceeded the maximum line size")}
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    line = state.buffer <> chunk
    state = %{state | buffer: ""}

    cond do
      byte_size(line) > @max_line_bytes ->
        {:noreply, fail(state, "System probe output exceeded the maximum line size")}

      String.trim(line) == "" ->
        {:noreply, state}

      true ->
        {:noreply, consume_line(line, state)}
    end
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state),
    do: {:noreply, fail(%{state | port: nil}, "System probe exited (status #{code}); retrying")}

  def handle_info({:EXIT, port, reason}, %{port: port} = state),
    do: {:noreply, fail(%{state | port: nil}, "System probe connection lost: #{inspect(reason)}")}

  def handle_info(:retry_probe, state),
    do: {:noreply, start_probe(%{state | retry_ref: nil})}

  # A closed port can leave an EXIT and an exit_status queued; neither should
  # affect the replacement process or create a second retry timer.
  def handle_info({port, _message}, state) when is_port(port), do: {:noreply, state}
  def handle_info({:EXIT, port, _reason}, state) when is_port(port), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_port(state.port)
    if state.retry_ref, do: Process.cancel_timer(state.retry_ref)
    if state.sample_timer, do: Process.cancel_timer(state.sample_timer)
    :ok
  end

  defp collect_linux(state) do
    case Linux.sample(state.linux_options) do
      {:ok, raw} ->
        state = consume_raw(raw, state)
        timer = Process.send_after(self(), :sample, state.sample_interval_ms)
        %{state | sample_timer: timer}

      {:error, message} ->
        fail(state, message)
    end
  end

  defp start_probe(%{platform: {:ok, %{kind: :proc}}} = state), do: collect_linux(state)

  defp start_probe(state) do
    case Probe.ensure(state) do
      :ok -> open_probe(state)
      {:error, message, retry?} -> fail(state, message, retry?)
    end
  end

  defp open_probe(state) do
    path = state.probe_path |> Path.expand() |> String.to_charlist()

    port =
      Port.open({:spawn_executable, path}, [
        :binary,
        {:line, 65_536},
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, []}
      ])

    %{state | port: port, previous: nil, buffer: ""}
  rescue
    error in [ArgumentError, ErlangError] ->
      fail(state, "Could not start system probe: #{Exception.message(error)}")
  end

  defp consume_line(line, state) do
    case Jason.decode(line) do
      {:ok, raw} -> consume_raw(raw, state)
      {:error, _reason} -> fail(state, "System probe returned invalid JSON")
    end
  end

  defp consume_raw(raw, state) do
    case raw do
      %{"error" => message} when is_binary(message) ->
        fail(state, "Native probe reported an error: #{message}")

      %{
        "timestamp_ms" => timestamp,
        "monotonic_ms" => monotonic,
        "cores" => cores,
        "memory" => memory
      } = raw
      when is_integer(timestamp) and is_integer(monotonic) and is_list(cores) and is_map(memory) ->
        sample = Metrics.sample(raw, state.previous)
        history = Enum.take(state.value.history ++ [sample], -60)

        value = %{
          status: if(is_nil(state.previous), do: "warming", else: "live"),
          error: "",
          sample: sample,
          history: history,
          samples: state.value.samples + 1
        }

        state = %{state | previous: raw, retry_ms: state.minimum}
        publish(state, value)

      _unexpected ->
        fail(state, "System probe returned incomplete data")
    end
  end

  defp fail(state, message, retry? \\ true) do
    close_port(state.port)
    state = %{state | port: nil, buffer: "", previous: nil}
    state = publish(state, %{state.value | status: "error", error: message})

    if retry? and is_nil(state.retry_ref) do
      timer = Process.send_after(self(), :retry_probe, state.retry_ms)
      %{state | retry_ref: timer, retry_ms: min(state.retry_ms * 2, state.maximum)}
    else
      state
    end
  end

  defp publish(state, value) do
    :ets.insert(state.cache, {:snapshot, value})
    state.broadcaster.(value)
    %{state | value: value}
  end

  defp broadcast(value), do: DomexSensor.Publisher.report(value)

  defp close_port(nil), do: :ok

  defp close_port(port) do
    Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp read_cache(table) do
    case :ets.lookup(table, :snapshot) do
      [{:snapshot, value}] -> value
      [] -> @empty
    end
  rescue
    ArgumentError -> @empty
  end
end
