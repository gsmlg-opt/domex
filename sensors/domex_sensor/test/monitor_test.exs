defmodule DomexSensor.MonitorTest do
  use ExUnit.Case, async: true
  alias DomexSensor.Monitor
  @moduletag :tmp_dir

  defp raw(index) do
    %{
      "timestamp_ms" => index * 1000,
      "monotonic_ms" => index * 1000,
      "model" => "Fixture Mac",
      "cpu_brand" => "Fixture CPU",
      "cores" => [
        %{
          "id" => 1,
          "user" => index * 20,
          "system" => index * 10,
          "nice" => 0,
          "idle" => index * 70
        }
      ],
      "memory" => %{},
      "disk" => %{"available" => false},
      "network" => %{"available" => false},
      "gpu" => []
    }
  end

  defp fixture(directory, lines, ending \\ "while IFS= read -r line; do :; done\n") do
    data = Path.join(directory, "samples.jsonl")
    executable = Path.join(directory, "probe.sh")
    File.write!(data, Enum.join(lines, "\n") <> "\n")
    quoted = "'" <> String.replace(data, "'", "'\\''") <> "'"
    File.write!(executable, "#!/bin/sh\ncat #{quoted}\n#{ending}")
    File.chmod!(executable, 0o700)
    executable
  end

  defp options(executable, parent) do
    [
      name: nil,
      probe_path: executable,
      skip_build: true,
      os_type: {:unix, :darwin},
      architecture: "arm64",
      broadcaster: &send(parent, {:sample, &1}),
      restart_min_ms: 60_000
    ]
  end

  test "converts port output to metrics and bounds history at sixty samples", %{
    tmp_dir: directory
  } do
    executable = fixture(directory, for(index <- 1..70, do: Jason.encode!(raw(index))))
    monitor = start_supervised!({Monitor, options(executable, self())})

    assert_receive {:sample, %{status: "warming", samples: 1, sample: %{cpu: %{total: nil}}}},
                   2000

    assert_receive {:sample, %{status: "live", samples: 2, sample: %{cpu: %{total: 30.0}}}}, 2000
    assert_receive {:sample, %{samples: 70}}, 2000
    assert %{history: history} = Monitor.snapshot(monitor)
    assert Enum.map(history, & &1.timestamp_ms) == Enum.map(11..70, &(&1 * 1000))
  end

  test "reassembles JSON split across port line boundaries", %{tmp_dir: directory} do
    model = String.duplicate("M", 70_000)
    executable = fixture(directory, [raw(1) |> Map.put("model", model) |> Jason.encode!()])
    start_supervised!({Monitor, options(executable, self())})
    assert_receive {:sample, %{sample: %{model: ^model}}}, 2000
  end

  test "probe exit preserves readings and rebaselines counters after restart", %{
    tmp_dir: directory
  } do
    executable = fixture(directory, [Jason.encode!(raw(1))], "exit 7\n")
    monitor = start_supervised!({Monitor, options(executable, self())})
    assert_receive {:sample, %{samples: 1}}, 2000
    assert_receive {:sample, %{status: "error", error: error, history: [_]}}, 2000
    assert error =~ "7"
    send(monitor, :retry_probe)

    assert_receive {:sample, %{status: "warming", samples: 2, sample: %{cpu: %{total: nil}}}},
                   2000
  end

  test "malformed JSON and oversized output become visible collector errors", %{
    tmp_dir: directory
  } do
    for {lines, error} <- [
          {["invalid JSON"], "JSON"},
          {[String.duplicate("x", 1_048_577)], "maximum line size"}
        ] do
      executable = fixture(directory, lines)
      monitor = start_supervised!({Monitor, options(executable, self())}, id: error)
      assert_receive {:sample, %{status: "error", sample: nil, error: message}}, 2000
      assert message =~ error
      assert %{status: "error"} = Monitor.snapshot(monitor)
      stop_supervised!(error)
    end
  end

  test "unsupported platforms report errors without trying to build a probe" do
    opts = options("unused", self()) |> Keyword.put(:os_type, {:win32, :nt})
    monitor = start_supervised!({Monitor, opts})
    assert_receive {:sample, %{status: "error", error: message}}
    assert message =~ "Unsupported platform"
    assert :sys.get_state(monitor).retry_ref == nil
  end
end
