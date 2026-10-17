defmodule DomexWeb.DashboardLiveTest do
  use DomexWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Domex.Device.Shadow
  alias Domex.PubSub

  setup do
    for %Shadow{id: id} <- Domex.list_devices() do
      Domex.remove_device(id)
    end

    :ok
  end

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

  test "clicking Discover button triggers discovery and shows flash notification", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#btn-discover")
    render_click(element(view, "#btn-discover"))

    assert render(view) =~ "Discovery sweep broadcasted to local network"
  end

  test "clicking Add Device button opens and closes the add device modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#add-device-form")

    assert has_element?(view, "#btn-add-device")
    render_click(element(view, "#btn-add-device"))

    assert has_element?(view, "#add-device-form")
    assert has_element?(view, "#btn-modal-close")
    assert has_element?(view, "#btn-modal-cancel")
    assert has_element?(view, "#btn-modal-submit")

    render_click(element(view, "#btn-modal-close"))
    refute has_element?(view, "#add-device-form")

    # Re-open and close with cancel button
    render_click(element(view, "#btn-add-device"))
    assert has_element?(view, "#add-device-form")

    render_click(element(view, "#btn-modal-cancel"))
    refute has_element?(view, "#add-device-form")
  end

  test "empty state Scan Network and Add Manually buttons work", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#btn-empty-scan")
    render_click(element(view, "#btn-empty-scan"))
    assert render(view) =~ "Discovery sweep broadcasted to local network"

    assert has_element?(view, "#btn-empty-add")
    render_click(element(view, "#btn-empty-add"))
    assert has_element?(view, "#add-device-form")

    render_click(element(view, "#btn-modal-close"))
    refute has_element?(view, "#add-device-form")
  end

  test "submitting add device form creates device and closes modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(element(view, "#btn-add-device"))
    assert has_element?(view, "#add-device-form")

    new_id = "test_form_lamp_#{:erlang.unique_integer([:positive])}"

    render_submit(element(view, "#add-device-form"), %{
      "device" => %{
        "id" => new_id,
        "name" => "Corner Reading Lamp",
        "type" => "light",
        "adapter" => "Domex.Adapter.YeelightLan",
        "host" => "192.168.1.199",
        "port" => "55443"
      }
    })

    refute has_element?(view, "#add-device-form")
    assert render(view) =~ "Corner Reading Lamp"
    assert render(view) =~ "Device &#39;Corner Reading Lamp&#39; created"

    Domex.remove_device(new_id)
  end
end
