defmodule DomexSensor.MetricsTest do
  use ExUnit.Case, async: true

  alias DomexSensor.Metrics

  defp raw do
    %{
      "timestamp_ms" => 1_000,
      "monotonic_ms" => 1_000,
      "model" => "Mac14,12",
      "cpu_brand" => "Apple M2 Pro",
      "processes" => 420,
      "threads" => 1_200,
      "threads_complete" => false,
      "processes_readable" => 350,
      "cores" => [
        %{"id" => 1, "user" => 100, "system" => 50, "nice" => 10, "idle" => 840},
        %{"id" => 2, "user" => 200, "system" => 100, "nice" => 0, "idle" => 700}
      ],
      "memory" => %{
        "physical" => 16_000,
        "anonymous" => 6_000,
        "purgeable" => 1_000,
        "wired" => 2_000,
        "compressed" => 1_000,
        "file_backed" => 3_000,
        "swap_used" => 1_000,
        "swap_total" => 4_000,
        "pressure" => 2
      },
      "disk" => %{
        "read_bytes" => 1_000,
        "write_bytes" => 2_000,
        "read_ops" => 10,
        "write_ops" => 20,
        "devices" => ["disk0"],
        "available" => true
      },
      "network" => %{
        "interfaces" => [
          %{
            "name" => "en0",
            "rx_bytes" => 10_000,
            "tx_bytes" => 5_000,
            "rx_packets" => 100,
            "tx_packets" => 50
          }
        ],
        "available" => true
      },
      "gpu" => [%{"name" => "Apple M2 Pro", "utilization" => nil}]
    }
  end

  defp advanced do
    raw()
    |> Map.merge(%{"timestamp_ms" => 3_500, "monotonic_ms" => 3_500})
    |> put_in(["cores"], [
      %{"id" => 1, "user" => 120, "system" => 60, "nice" => 15, "idle" => 905},
      %{"id" => 2, "user" => 400, "system" => 200, "nice" => 0, "idle" => 1_400}
    ])
    |> put_in(["disk", "read_bytes"], 3_500)
    |> put_in(["disk", "write_bytes"], 7_000)
    |> put_in(["disk", "read_ops"], 15)
    |> put_in(["disk", "write_ops"], 30)
    |> put_in(["network", "interfaces"], [
      %{
        "name" => "en0",
        "rx_bytes" => 15_000,
        "tx_bytes" => 7_500,
        "rx_packets" => 150,
        "tx_packets" => 75
      }
    ])
  end

  test "preserves reported performance and efficiency types on their original core IDs" do
    input =
      update_in(raw(), ["cores"], fn [first, second] ->
        [Map.put(first, "type", "efficiency"), Map.put(second, "type", "performance")]
      end)

    assert %{cores: [%{id: 1, type: "efficiency"}, %{id: 2, type: "performance"}]} =
             Metrics.sample(input)
  end

  test "missing or unrecognized core types stay unknown even on an Apple CPU" do
    input = put_in(raw(), ["cores", Access.at(0), "type"], "unexpected")
    assert %{cores: [%{type: nil}, %{type: nil}]} = Metrics.sample(input)
  end

  test "first sample preserves real gauges while percentages and rates are unknown" do
    assert %{
             timestamp_ms: 1_000,
             model: "Mac14,12",
             cpu_brand: "Apple M2 Pro",
             cpu: %{user: nil, system: nil, idle: nil, total: nil},
             cores: [%{id: 1, total: nil}, %{id: 2, total: nil}],
             disk: %{read_bytes: 1_000, read_bps: nil},
             network: %{rx_bytes: 10_000, rx_bps: nil},
             processes: 420,
             threads: 1_200,
             threads_complete: false,
             processes_readable: 350,
             gpu: [%{name: "Apple M2 Pro", utilization: nil}]
           } = Metrics.sample(raw(), nil)
  end

  test "CPU includes nice in user and weights aggregate by actual delta ticks" do
    assert %{
             cores: [
               %{user: 25.0, system: 10.0, idle: 65.0, total: 35.0},
               %{user: 20.0, system: 10.0, idle: 70.0, total: 30.0}
             ],
             cpu: cpu
           } = Metrics.sample(advanced(), raw())

    assert_in_delta cpu.user, 225 / 1_100 * 100, 0.000001
    assert_in_delta cpu.system, 110 / 1_100 * 100, 0.000001
    assert_in_delta cpu.total, 335 / 1_100 * 100, 0.000001
  end

  test "rates use the measured 2.5 seconds rather than assuming one second" do
    assert %{
             disk: %{read_bps: 1_000.0, write_bps: 2_000.0, read_iops: 2.0, write_iops: 4.0},
             network: %{rx_bps: 2_000.0, tx_bps: 1_000.0, rx_pps: 20.0, tx_pps: 10.0}
           } = Metrics.sample(advanced(), raw())
  end

  test "memory uses Activity Monitor approximation and direct pressure codes" do
    assert %{
             memory: %{
               physical: 16_000,
               app: 5_000,
               wired: 2_000,
               compressed: 1_000,
               used: 8_000,
               cached: 4_000,
               swap_used: 1_000,
               swap_total: 4_000,
               pressure: 2,
               percent: 50.0
             }
           } = Metrics.sample(raw())

    assert %{memory: %{app: 0, percent: 100.0, pressure: nil}} =
             raw()
             |> put_in(["memory", "anonymous"], 10)
             |> put_in(["memory", "physical"], 20)
             |> put_in(["memory", "pressure"], 99)
             |> Metrics.sample()
  end

  test "unknown memory and counters remain nil, never fabricated zeroes" do
    assert %{
             memory: %{app: nil, used: nil, cached: nil, percent: nil},
             processes: nil,
             threads: nil,
             disk: %{read_bytes: nil, read_bps: nil},
             network: %{rx_bytes: nil, rx_bps: nil}
           } =
             Metrics.sample(%{"memory" => %{"physical" => 0}, "disk" => %{"available" => false}})
  end

  test "zero tick deltas and regressed CPU counters rebaseline" do
    assert %{cpu: %{total: nil}, cores: [%{total: nil}, %{total: nil}]} =
             Metrics.sample(Map.put(raw(), "monotonic_ms", 2_000), raw())

    current = put_in(advanced(), ["cores", Access.at(0), "user"], 90)

    assert %{cpu: %{total: nil}, cores: [%{total: nil}, %{total: 30.0}]} =
             Metrics.sample(current, raw())
  end

  test "CPU topology changes cannot be compared as an unchanged machine" do
    current = update_in(advanced(), ["cores"], &Enum.drop(&1, 1))
    assert %{cpu: %{total: nil}, cores: [%{id: 2, total: nil}]} = Metrics.sample(current, raw())
  end

  test "nonpositive elapsed time invalidates all rates and CPU comparisons" do
    for monotonic <- [1_000, 999, nil] do
      assert %{cpu: %{total: nil}, disk: %{read_bps: nil}, network: %{rx_bps: nil}} =
               Metrics.sample(Map.put(advanced(), "monotonic_ms", monotonic), raw())
    end
  end

  test "disk resets and device changes do not produce throughput spikes" do
    assert %{disk: %{read_bytes: 2, read_bps: nil, write_bps: 2_000.0}} =
             Metrics.sample(put_in(advanced(), ["disk", "read_bytes"], 2), raw())

    assert %{disk: %{read_bps: nil, write_bps: nil}} =
             Metrics.sample(put_in(advanced(), ["disk", "devices"], ["disk0", "disk1"]), raw())
  end

  test "interface churn compares only matching interfaces before summing deltas" do
    old_iface = %{
      "name" => "gone",
      "rx_bytes" => 100_000,
      "tx_bytes" => 200_000,
      "rx_packets" => 100,
      "tx_packets" => 200
    }

    new_iface = %{
      "name" => "new",
      "rx_bytes" => 9_000_000_000,
      "tx_bytes" => 8_000_000_000,
      "rx_packets" => 9_000,
      "tx_packets" => 8_000
    }

    previous = update_in(raw(), ["network", "interfaces"], &[old_iface | &1])
    current = update_in(advanced(), ["network", "interfaces"], &[new_iface | &1])

    assert %{
             network: %{
               interfaces: ["new", "en0"],
               rx_bps: 2_000.0,
               tx_bps: 1_000.0,
               rx_bytes: 9_000_015_000
             }
           } = Metrics.sample(current, previous)

    assert %{network: %{rx_bps: nil, tx_bps: nil}} =
             Metrics.sample(put_in(current, ["network", "interfaces"], [new_iface]), previous)
  end

  test "a reset on a matching interface is unknown instead of negative traffic" do
    current = put_in(advanced(), ["network", "interfaces", Access.at(0), "rx_bytes"], 10)
    assert %{network: %{rx_bps: nil, tx_bps: 1_000.0}} = Metrics.sample(current, raw())
  end

  test "GPU only exposes actual bounded utilization and never substitutes unknown values" do
    current =
      Map.put(raw(), "gpu", [
        %{"name" => "GPU A", "utilization" => 37.5},
        %{"name" => "GPU B", "utilization" => 101},
        %{"name" => "GPU C", "utilization" => nil}
      ])

    assert %{
             gpu: [
               %{name: "GPU A", utilization: 37.5},
               %{name: "GPU B", utilization: nil},
               %{name: "GPU C", utilization: nil}
             ]
           } = Metrics.sample(current)
  end
end
