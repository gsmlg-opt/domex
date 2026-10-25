defmodule DomexSensor.Metrics do
  @moduledoc "Converts cumulative native counters into nullable, client-safe metrics."

  @cpu_fields ["user", "system", "nice", "idle"]

  def sample(raw, previous \\ nil) when is_map(raw) do
    elapsed = elapsed_seconds(raw, previous)
    raw_cores = maps(raw["cores"])
    previous_cores = if is_map(previous), do: maps(previous["cores"]), else: []
    comparable = elapsed != nil and same_cores?(raw_cores, previous_cores)
    old_by_id = Map.new(previous_cores, &{&1["id"], &1})

    deltas = Enum.map(raw_cores, &cpu_delta(&1, old_by_id[&1["id"]], comparable))

    cores =
      Enum.zip(raw_cores, deltas)
      |> Enum.map(fn {core, delta} ->
        Map.merge(cpu_percentages(delta), %{id: core["id"], type: core_type(core["type"])})
      end)

    aggregate =
      if deltas != [] and Enum.all?(deltas, &is_map/1) do
        Enum.reduce(deltas, %{user: 0, system: 0, idle: 0}, fn delta, acc ->
          Map.new(acc, fn {key, value} -> {key, value + delta[key]} end)
        end)
      end

    %{
      timestamp_ms: counter(raw["timestamp_ms"]),
      model: text(raw["model"]),
      cpu_brand: text(raw["cpu_brand"]),
      processes: counter(raw["processes"]),
      threads: counter(raw["threads"]),
      threads_complete: raw["threads_complete"] == true,
      processes_readable: counter(raw["processes_readable"]),
      cores: cores,
      cpu: cpu_percentages(aggregate),
      memory: memory(raw["memory"]),
      disk: disk(raw["disk"], get_map(previous, "disk"), elapsed),
      network: network(raw["network"], get_map(previous, "network"), elapsed),
      gpu:
        Enum.map(
          maps(raw["gpu"]),
          &%{name: text(&1["name"]), utilization: utilization(&1["utilization"])}
        )
    }
  end

  defp elapsed_seconds(raw, previous) when is_map(previous) do
    case {raw["monotonic_ms"], previous["monotonic_ms"]} do
      {now, before} when is_integer(now) and is_integer(before) and now > before ->
        (now - before) / 1_000

      _ ->
        nil
    end
  end

  defp elapsed_seconds(_raw, _previous), do: nil

  defp core_type(type) when type in ["performance", "efficiency"], do: type
  defp core_type(_), do: nil

  defp same_cores?(current, previous) do
    ids = Enum.map(current, & &1["id"])
    old_ids = Enum.map(previous, & &1["id"])

    ids != [] and Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and
      length(Enum.uniq(ids)) == length(ids) and Enum.sort(ids) == Enum.sort(old_ids)
  end

  defp cpu_delta(current, previous, true) when is_map(previous) do
    changes = Enum.map(@cpu_fields, &delta(current[&1], previous[&1]))

    case changes do
      [user, system, nice, idle]
      when is_number(user) and is_number(system) and is_number(nice) and is_number(idle) ->
        if user + system + nice + idle > 0,
          do: %{user: user + nice, system: system, idle: idle}

      _ ->
        nil
    end
  end

  defp cpu_delta(_current, _previous, _comparable), do: nil

  defp cpu_percentages(%{user: user, system: system, idle: idle}) do
    total = user + system + idle

    %{
      user: percentage(user, total),
      system: percentage(system, total),
      idle: percentage(idle, total),
      total: percentage(user + system, total)
    }
  end

  defp cpu_percentages(_), do: %{user: nil, system: nil, idle: nil, total: nil}

  defp memory(value) do
    raw = as_map(value)
    physical = counter(raw["physical"])
    app = counter(raw["app"]) || subtract_floor(raw["anonymous"], raw["purgeable"])
    wired = counter(raw["wired"])
    compressed = counter(raw["compressed"])
    used = counter(raw["used"]) || sum_known([app, wired, compressed])

    %{
      physical: physical,
      used: used,
      app: app,
      wired: wired,
      compressed: compressed,
      cached:
        counter(raw["cached"]) ||
          sum_known([counter(raw["file_backed"]), counter(raw["purgeable"])]),
      swap_used: counter(raw["swap_used"]),
      swap_total: counter(raw["swap_total"]),
      pressure: if(raw["pressure"] in [1, 2, 4], do: raw["pressure"]),
      percent: percentage(used, physical)
    }
  end

  defp disk(value, old_value, elapsed) do
    raw = as_map(value)
    old = as_map(old_value)
    devices = strings(raw["devices"])

    comparable =
      raw["available"] == true and old["available"] == true and
        Enum.sort(devices) == Enum.sort(strings(old["devices"]))

    %{
      read_bytes: counter(raw["read_bytes"]),
      write_bytes: counter(raw["write_bytes"]),
      read_ops: counter(raw["read_ops"]),
      write_ops: counter(raw["write_ops"]),
      read_bps: rate(raw["read_bytes"], old["read_bytes"], elapsed, comparable),
      write_bps: rate(raw["write_bytes"], old["write_bytes"], elapsed, comparable),
      read_iops: rate(raw["read_ops"], old["read_ops"], elapsed, comparable),
      write_iops: rate(raw["write_ops"], old["write_ops"], elapsed, comparable),
      devices: devices,
      available: raw["available"] == true
    }
  end

  defp network(value, old_value, elapsed) do
    raw = as_map(value)
    old = as_map(old_value)
    interfaces = named_interfaces(raw["interfaces"])
    previous = Map.new(named_interfaces(old["interfaces"]), &{&1["name"], &1})
    current_available = raw["available"] == true
    comparable = current_available and old["available"] == true and elapsed != nil
    shared = Enum.filter(interfaces, &Map.has_key?(previous, &1["name"]))

    totals = fn key ->
      if current_available and interfaces != [],
        do: sum_known(Enum.map(interfaces, &counter(&1[key])))
    end

    rates = fn key ->
      if comparable and shared != [] do
        changes = Enum.map(shared, &delta(&1[key], previous[&1["name"]][key]))

        case sum_known(changes) do
          nil -> nil
          total -> total / elapsed
        end
      end
    end

    %{
      rx_bytes: totals.("rx_bytes"),
      tx_bytes: totals.("tx_bytes"),
      rx_packets: totals.("rx_packets"),
      tx_packets: totals.("tx_packets"),
      rx_bps: rates.("rx_bytes"),
      tx_bps: rates.("tx_bytes"),
      rx_pps: rates.("rx_packets"),
      tx_pps: rates.("tx_packets"),
      interfaces: Enum.map(interfaces, & &1["name"]),
      available: current_available
    }
  end

  defp named_interfaces(value) do
    value |> maps() |> Enum.filter(&(is_binary(&1["name"]) and &1["name"] != ""))
  end

  defp rate(now, before, elapsed, true) when is_number(elapsed) and elapsed > 0 do
    case delta(now, before) do
      nil -> nil
      value -> value / elapsed
    end
  end

  defp rate(_now, _before, _elapsed, _comparable), do: nil

  defp delta(now, before)
       when is_integer(now) and is_integer(before) and now >= before and before >= 0,
       do: now - before

  defp delta(_now, _before), do: nil

  defp percentage(value, total) when is_number(value) and is_number(total) and total > 0,
    do: max(0.0, min(100.0, value / total * 100.0))

  defp percentage(_value, _total), do: nil

  defp utilization(value) when is_number(value) and value >= 0 and value <= 100, do: value
  defp utilization(_value), do: nil

  defp subtract_floor(a, b) when is_integer(a) and is_integer(b) and a >= 0 and b >= 0,
    do: max(a - b, 0)

  defp subtract_floor(_a, _b), do: nil

  defp sum_known(values) do
    if Enum.all?(values, &(is_number(&1) and &1 >= 0)), do: Enum.sum(values)
  end

  defp get_map(value, key) when is_map(value), do: value[key]
  defp get_map(_value, _key), do: nil
  defp counter(value) when is_integer(value) and value >= 0, do: value
  defp counter(_value), do: nil
  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil
  defp as_map(value) when is_map(value), do: value
  defp as_map(_value), do: %{}
  defp maps(value) when is_list(value), do: Enum.filter(value, &is_map/1)
  defp maps(_value), do: []
  defp strings(value) when is_list(value), do: Enum.filter(value, &is_binary/1)
  defp strings(_value), do: []
end
