defmodule DomexSensor.LinuxTest do
  use ExUnit.Case, async: true
  alias DomexSensor.{Linux, Metrics}
  @moduletag :tmp_dir

  setup %{tmp_dir: directory} do
    proc = Path.join(directory, "proc")
    sys = Path.join(directory, "sys")
    File.mkdir_p!(Path.join(proc, "net"))
    File.mkdir_p!(Path.join(proc, "42"))
    File.mkdir_p!(Path.join(sys, "block/sda"))

    File.write!(
      Path.join(proc, "stat"),
      "cpu 10 2 3 80 5 1 2 3 0 0\ncpu0 10 2 3 80 5 1 2 3 0 0\n"
    )

    File.write!(
      Path.join(proc, "meminfo"),
      "MemTotal: 16000 kB\nMemAvailable: 6000 kB\nAnonPages: 5000 kB\nCached: 2000 kB\nBuffers: 1000 kB\nSReclaimable: 500 kB\nSwapTotal: 4000 kB\nSwapFree: 3000 kB\n"
    )

    File.write!(Path.join(proc, "cpuinfo"), "model name : Fixture CPU\n")

    File.write!(
      Path.join(proc, "diskstats"),
      "8 0 sda 10 0 20 0 30 0 40 0 0 0 0\n8 1 sda1 100 0 200 0 300 0 400 0 0 0 0\n"
    )

    File.write!(
      Path.join(proc, "net/dev"),
      "Inter-| Receive | Transmit\nlo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0\n eth0: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"
    )

    File.write!(Path.join(proc, "42/status"), "Name: fixture\nThreads: 3\n")
    %{options: [proc_dir: proc, sys_dir: sys], proc: proc}
  end

  test "reports real gauges and cumulative counters without double counting partitions", %{
    options: options
  } do
    assert {:ok, raw} = Linux.sample(options)
    assert [%{"id" => 1, "user" => 10, "nice" => 2, "system" => 9, "idle" => 85}] = raw["cores"]
    assert raw["disk"]["read_bytes"] == 20 * 512
    assert raw["disk"]["devices"] == ["sda"]

    assert [%{"name" => "eth0", "rx_bytes" => 1000, "tx_bytes" => 2000}] =
             raw["network"]["interfaces"]

    assert raw["processes"] == 1
    assert raw["threads"] == 3
    assert raw["threads_complete"]
    sample = Metrics.sample(raw)
    assert sample.memory.physical == 16000 * 1024
    assert sample.memory.used == 10000 * 1024
    assert sample.memory.percent == 62.5
    assert sample.memory.cached == 3500 * 1024
    assert sample.memory.swap_used == 1000 * 1024
    assert sample.memory.wired == nil
    assert sample.cpu.total == nil
    assert sample.gpu == []
  end

  test "optional missing counters stay unavailable while required procfs files report errors", %{
    options: options,
    proc: proc
  } do
    File.rm!(Path.join(proc, "diskstats"))
    File.rm!(Path.join(proc, "net/dev"))
    assert {:ok, raw} = Linux.sample(options)
    assert raw["disk"] == %{"available" => false}
    assert raw["network"]["available"] == false
    File.rm!(Path.join(proc, "stat"))
    assert {:error, message} = Linux.sample(options)
    assert message =~ "procfs"
  end
end
