defmodule DomexWeb.SensorsLiveTest do
  use DomexWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Domex.Sensor.Store

  test "shows sensor setup and navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sensors")
    assert has_element?(view, "#sensors-page")
    assert has_element?(view, "#sensors-empty")
    assert has_element?(view, "#nav-sensors")
    assert has_element?(view, "#sensors-dashboard")
  end

  test "streams MQTT sensor readings and availability changes into the view", %{conn: conn} do
    id = "sensor-live-#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/sensors")

    sample = %{
      "timestamp_ms" => 1000,
      "cpu_brand" => "Apple M2",
      "model" => "Mac14,12",
      "cpu" => %{"total" => 30.0},
      "cores" => [%{"id" => 1, "total" => 30.0, "type" => "performance"}],
      "memory" => %{"percent" => 50.0, "used" => 8000, "physical" => 16000},
      "disk" => %{},
      "network" => %{},
      "gpu" => [%{"name" => "Apple M2", "utilization" => nil}]
    }

    state = %{
      "name" => "Desk Mac",
      "hostname" => "desk.local",
      "platform" => "darwin-arm64",
      "status" => "live",
      "error" => "",
      "sample" => sample
    }

    Store.ingest(id, {:state, state})
    Store.ingest(id, {:availability, true})
    assert {:ok, _sensor} = Store.get(id)
    assert has_element?(view, "#sensor-#{id}")
    assert has_element?(view, "#sensor-cpu-#{id}", "30.0%")
    assert has_element?(view, "#sensor-memory-#{id}", "50.0%")
    assert has_element?(view, "#sensor-availability-#{id}", "Online")
    assert has_element?(view, "#sensor-history-#{id}")
    refute has_element?(view, "#sensor-#{id} button[phx-click=toggle]")
    Store.ingest(id, {:availability, false})
    assert {:ok, _offline} = Store.get(id)
    assert has_element?(view, "#sensor-availability-#{id}", "Offline")
    assert has_element?(view, "#sensor-cpu-#{id}", "30.0%")
  end
end
