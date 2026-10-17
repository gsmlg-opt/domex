defmodule DomexWeb.DashboardLiveTest do
  use DomexWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Domex.Device.Shadow
  alias Domex.PubSub

  test "renders dashboard with title and action buttons", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Domex"
    assert html =~ "Local Hub"
    assert html =~ "Discover"
    assert html =~ "Add Device"
  end

  test "real-time push updates via PubSub without polling", %{conn: conn} do
    id = "live_test_bulb_#{:erlang.unique_integer([:positive])}"

    {:ok, _shadow} =
      Domex.add_device(%{
        id: id,
        name: "Desk Study Lamp",
        type: :light,
        adapter: Domex.Adapter.YeelightLan,
        host: "192.168.1.150",
        port: 55443
      })

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Desk Study Lamp"

    # Now broadcast a shadow update via PubSub
    updated_shadow = %Shadow{
      id: id,
      name: "Desk Study Lamp",
      type: :light,
      adapter: Domex.Adapter.YeelightLan,
      host: "192.168.1.150",
      port: 55443,
      online?: true,
      power: true,
      brightness: 92,
      color_temp: 4500
    }

    PubSub.broadcast_shadow(updated_shadow)

    # Rendered view should reflect the push update immediately
    assert render(view) =~ "92%"
    assert render(view) =~ "4500K"
    assert render(view) =~ "Online"

    Domex.remove_device(id)
  end

  test "navigates to device detail page", %{conn: conn} do
    id = "live_test_ac_#{:erlang.unique_integer([:positive])}"

    {:ok, _shadow} =
      Domex.add_device(%{
        id: id,
        name: "Master Bedroom AC",
        type: :climate,
        adapter: Domex.Adapter.MideaDevice,
        host: "192.168.1.180",
        port: 6444
      })

    {:ok, _view, html} = live(conn, ~p"/devices/#{id}")
    assert html =~ "Master Bedroom AC"
    assert html =~ "Operating Mode"
    assert html =~ "Fan Speed"
    assert html =~ "192.168.1.180:6444"

    Domex.remove_device(id)
  end
end
