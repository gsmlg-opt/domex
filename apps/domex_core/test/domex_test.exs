defmodule DomexTest do
  use ExUnit.Case, async: false

  alias Domex.Device.Shadow

  test "add_device, get_device, list_devices, and remove_device integration" do
    id = "domex_test_dev_#{:erlang.unique_integer([:positive])}"

    attrs = %{
      id: id,
      name: "Living Room Light",
      type: :light,
      adapter: Domex.Adapter.YeelightLan,
      host: "127.0.0.1",
      port: 55443
    }

    assert {:ok, %Shadow{id: ^id, name: "Living Room Light"}} = Domex.add_device(attrs)

    assert {:ok, shadow} = Domex.get_device(id)
    assert shadow.name == "Living Room Light"
    assert shadow.type == :light

    devices = Domex.list_devices()
    assert Enum.any?(devices, fn d -> d.id == id end)

    # Test optimistic power toggle
    Domex.toggle(id)
    {:ok, updated_shadow} = Domex.get_device(id)
    assert updated_shadow.power == true

    # Test optimistic brightness
    Domex.set_brightness(id, 80)
    {:ok, bright_shadow} = Domex.get_device(id)
    assert bright_shadow.brightness == 80

    # Test optimistic color temp
    Domex.set_color_temp(id, 3500)
    {:ok, ct_shadow} = Domex.get_device(id)
    assert ct_shadow.color_temp == 3500

    # Test optimistic RGB
    Domex.set_rgb(id, 0x00FF00)
    {:ok, rgb_shadow} = Domex.get_device(id)
    assert rgb_shadow.rgb == 0x00FF00

    # Remove device
    assert :ok = Domex.remove_device(id)
    assert {:error, :not_found} = Domex.get_device(id)
  end

  test "climate AC control facade" do
    id = "domex_test_ac_#{:erlang.unique_integer([:positive])}"

    attrs = %{
      id: id,
      name: "Bedroom AC",
      type: :climate,
      adapter: Domex.Adapter.MideaDevice,
      host: "127.0.0.1",
      port: 6444
    }

    assert {:ok, %Shadow{id: ^id, name: "Bedroom AC"}} = Domex.add_device(attrs)

    Domex.set_ac(id, %{target_temp: 22.5, mode: :cool, fan_speed: :high})
    {:ok, ac_shadow} = Domex.get_device(id)
    assert ac_shadow.ac_target_temp == 22.5
    assert ac_shadow.ac_mode == :cool
    assert ac_shadow.ac_fan_speed == :high

    Domex.remove_device(id)
  end
end
