defmodule Domex.Sensor.StoreTest do
  use ExUnit.Case, async: true
  alias Domex.Sensor.Store

  setup do
    parent = self()
    store = start_supervised!({Store, name: nil, sweep_ms: 60_000, broadcast: &send(parent, &1)})
    %{store: store}
  end

  defp snapshot(index) do
    %{
      "name" => "Desk Mac",
      "hostname" => "desk.local",
      "platform" => "darwin-arm64",
      "status" => "live",
      "error" => "",
      "sample" => %{"timestamp_ms" => index, "cpu" => %{"total" => 30.0}}
    }
  end

  test "retained snapshots do not override offline availability, regardless of message order", %{
    store: store
  } do
    Store.ingest("mac", {:availability, false}, store)
    Store.ingest("mac", {:state, snapshot(1)}, store)
    assert {:ok, %{online?: false, sample: %{"timestamp_ms" => 1}}} = Store.get("mac", store)
    Store.ingest("mac", {:availability, true}, store)
    assert {:ok, %{online?: true}} = Store.get("mac", store)
    Store.ingest("mac", {:availability, false}, store)
    assert {:ok, %{online?: false}} = Store.get("mac", store)
  end

  test "history keeps only sixty distinct samples and survives disconnects", %{store: store} do
    for index <- 1..70, do: Store.ingest("mac", {:state, snapshot(index)}, store)
    Store.ingest("mac", {:state, snapshot(70)}, store)
    Store.ingest("mac", {:availability, true}, store)
    Store.disconnected(store)
    assert {:ok, sensor} = Store.get("mac", store)
    refute sensor.online?
    assert Enum.map(sensor.history, & &1["timestamp_ms"]) == Enum.to_list(11..70)
  end

  test "stale sensors become offline and fresh samples restore known online availability", %{
    store: store
  } do
    Store.ingest("mac", {:state, snapshot(1)}, store)
    Store.ingest("mac", {:availability, true}, store)
    _ = :sys.get_state(store)

    :sys.replace_state(store, fn state ->
      put_in(state, [:sensors, "mac", :last_seen], System.monotonic_time(:millisecond) - 61_000)
    end)

    send(store, :expire)
    assert {:ok, %{online?: false}} = Store.get("mac", store)
    Store.ingest("mac", {:state, snapshot(2)}, store)
    assert {:ok, %{online?: true}} = Store.get("mac", store)
  end

  test "bounds the number of sensor identities" do
    store =
      start_supervised!({Store, name: nil, max_sensors: 1, broadcast: fn _ -> :ok end},
        id: :bounded
      )

    Store.ingest("first", {:state, snapshot(1)}, store)
    Store.ingest("second", {:state, snapshot(2)}, store)
    assert [%{id: "first"}] = Store.list(store)
  end
end
