defmodule DomexSensor.Linux do
  @moduledoc "Unprivileged Linux cumulative counters from procfs; unavailable readings stay nil."

  def sample(options \\ []) do
    proc = Keyword.get(options, :proc_dir, "/proc")
    sys = Keyword.get(options, :sys_dir, "/sys")

    with {:ok, stat} <- File.read(Path.join(proc, "stat")),
         {:ok, memory} <- File.read(Path.join(proc, "meminfo")) do
      {:ok,
       %{
         "timestamp_ms" => System.system_time(:millisecond),
         "monotonic_ms" => System.monotonic_time(:millisecond),
         "model" => model(sys),
         "cpu_brand" => cpu_brand(proc),
         "cores" => cores(stat),
         "memory" => memory(memory),
         "disk" => disk(proc, sys),
         "network" => network(proc),
         "gpu" => []
       }
       |> Map.merge(processes(proc))}
    else
      {:error, reason} -> {:error, "Could not read Linux procfs: #{:file.format_error(reason)}"}
    end
  end

  defp cores(stat) do
    stat
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case String.split(line) do
        ["cpu" <> id, user, nice, system, idle | rest] when id != "" ->
          case Integer.parse(id) do
            {index, ""} ->
              values = Enum.map(rest, &integer/1)

              [
                %{
                  "id" => index + 1,
                  "user" => integer(user),
                  "nice" => integer(nice),
                  "system" => integer(system) + Enum.sum(Enum.slice(values, 1, 3)),
                  "idle" => integer(idle) + Enum.at(values, 0, 0)
                }
              ]

            _ ->
              []
          end

        _ ->
          []
      end
    end)
  end

  defp memory(text) do
    values =
      text
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line) do
          [key, amount, "kB"] ->
            Map.put(acc, String.trim_trailing(key, ":"), integer(amount) * 1_024)

          _ ->
            acc
        end
      end)

    total = values["MemTotal"]
    available = values["MemAvailable"]

    %{
      "physical" => total,
      "used" => subtract(total, available),
      "app" => values["AnonPages"],
      "cached" => sum([values["Cached"], values["Buffers"], values["SReclaimable"]]),
      "swap_total" => values["SwapTotal"],
      "swap_used" => subtract(values["SwapTotal"], values["SwapFree"])
    }
  end

  defp disk(proc, sys) do
    with {:ok, devices} <- File.ls(Path.join(sys, "block")),
         {:ok, text} <- File.read(Path.join(proc, "diskstats")) do
      devices =
        Enum.reject(devices, &String.starts_with?(&1, ["loop", "ram", "dm-", "md", "zram"]))

      counters =
        text
        |> String.split("\n")
        |> Enum.flat_map(fn line ->
          case String.split(line) do
            [
              _major,
              _minor,
              device,
              reads,
              _merged,
              read_sectors,
              _read_ms,
              writes,
              _merged_writes,
              write_sectors | _
            ] ->
              if device in devices,
                do: [
                  %{
                    "name" => device,
                    "read_ops" => integer(reads),
                    "write_ops" => integer(writes),
                    "read_bytes" => integer(read_sectors) * 512,
                    "write_bytes" => integer(write_sectors) * 512
                  }
                ],
                else: []

            _ ->
              []
          end
        end)

      totals =
        Map.new(["read_ops", "write_ops", "read_bytes", "write_bytes"], fn key ->
          {key, if(counters != [], do: Enum.sum(Enum.map(counters, & &1[key])))}
        end)

      Map.merge(totals, %{
        "available" => counters != [],
        "devices" => Enum.map(counters, & &1["name"])
      })
    else
      _ -> %{"available" => false}
    end
  end

  defp network(proc) do
    case File.read(Path.join(proc, "net/dev")) do
      {:ok, text} ->
        interfaces =
          text
          |> String.split("\n")
          |> Enum.flat_map(fn line ->
            case String.split(line, ":", parts: 2) do
              [name, counters] ->
                name = String.trim(name)
                values = String.split(counters) |> Enum.map(&integer/1)

                if name != "lo" and length(values) >= 16,
                  do: [
                    %{
                      "name" => name,
                      "rx_bytes" => Enum.at(values, 0),
                      "rx_packets" => Enum.at(values, 1),
                      "tx_bytes" => Enum.at(values, 8),
                      "tx_packets" => Enum.at(values, 9)
                    }
                  ],
                  else: []

              _ ->
                []
            end
          end)

        %{"available" => true, "interfaces" => interfaces}

      _ ->
        %{"available" => false, "interfaces" => []}
    end
  end

  defp processes(proc) do
    case File.ls(proc) do
      {:ok, entries} ->
        pids = Enum.filter(entries, &Regex.match?(~r/\A\d+\z/, &1))

        threads =
          Enum.flat_map(pids, fn pid ->
            with {:ok, status} <- File.read(Path.join([proc, pid, "status"])),
                 [_, count] <- Regex.run(~r/^Threads:\s+(\d+)/m, status) do
              [integer(count)]
            else
              _ -> []
            end
          end)

        %{
          "processes" => length(pids),
          "threads" => if(threads != [], do: Enum.sum(threads)),
          "threads_complete" => length(threads) == length(pids),
          "processes_readable" => length(threads)
        }

      _ ->
        %{}
    end
  end

  defp model(sys) do
    ["devices/virtual/dmi/id/product_name", "firmware/devicetree/base/model"]
    |> Enum.find_value("Linux device", fn file ->
      case File.read(Path.join(sys, file)) do
        {:ok, text} -> String.trim(text, <<0>>) |> String.trim()
        _ -> nil
      end
    end)
  end

  defp cpu_brand(proc) do
    with {:ok, text} <- File.read(Path.join(proc, "cpuinfo")),
         [_, brand] <- Regex.run(~r/^(?:model name|Hardware|Processor)\s*:\s*(.+)$/m, text) do
      String.trim(brand)
    else
      _ -> to_string(:erlang.system_info(:system_architecture))
    end
  end

  defp integer(value), do: String.to_integer(value)
  defp subtract(a, b) when is_integer(a) and is_integer(b), do: max(a - b, 0)
  defp subtract(_, _), do: nil
  defp sum(values), do: if(Enum.all?(values, &is_integer/1), do: Enum.sum(values))
end
