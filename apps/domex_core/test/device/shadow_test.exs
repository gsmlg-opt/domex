defmodule Domex.Device.ShadowTest do
  use ExUnit.Case, async: true
  alias Domex.Device.Shadow

  describe "new/1" do
    test "initializes with sensible defaults and inferred type" do
      shadow =
        Shadow.new(%{id: "yeelight_1", adapter: Domex.Adapter.YeelightLan, host: "192.168.1.50"})

      assert shadow.id == "yeelight_1"
      assert shadow.type == :light
      assert shadow.adapter == Domex.Adapter.YeelightLan
      assert shadow.host == "192.168.1.50"
      assert shadow.online? == false
      assert shadow.power == false
    end

    test "explicit type takes precedence" do
      shadow = Shadow.new(%{id: "custom_switch", type: :switch})
      assert shadow.type == :switch
    end
  end

  describe "apply_event/2" do
    setup do
      shadow = Shadow.new(%{id: "test_dev", type: :light})
      {:ok, shadow: shadow}
    end

    test "handles {:online, bool}", %{shadow: shadow} do
      s1 = Shadow.apply_event(shadow, {:online, true})
      assert s1.online? == true

      s2 = Shadow.apply_event(s1, {:online, false})
      assert s2.online? == false
    end

    test "handles {:disconnected, reason}", %{shadow: shadow} do
      online = %{shadow | online?: true}
      s = Shadow.apply_event(online, {:disconnected, :tcp_closed})
      assert s.online? == false
    end

    test "handles {:props, map} for light properties", %{shadow: shadow} do
      props = %{"power" => "on", "bright" => "85", "ct" => "4000", "rgb" => 16_711_680}
      s = Shadow.apply_event(shadow, {:props, props})

      assert s.online? == true
      assert s.power == true
      assert s.brightness == 85
      assert s.color_temp == 4000
      assert s.rgb == 16_711_680
      assert s.properties["bright"] == "85"
    end

    test "handles {:state, map} for AC climate properties" do
      shadow = Shadow.new(%{id: "ac_1", type: :climate})

      state = %{
        power: true,
        target_temp: 23.5,
        indoor_temp: 25.0,
        mode: :cool,
        fan_speed: :auto,
        swing_vertical: true,
        swing_horizontal: false
      }

      s = Shadow.apply_event(shadow, {:state, state})

      assert s.online? == true
      assert s.power == true
      assert s.ac_target_temp == 23.5
      assert s.ac_temp == 25.0
      assert s.ac_mode == :cool
      assert s.ac_fan_speed == :auto
      assert s.ac_swing_vertical == true
      assert s.ac_swing_horizontal == false
    end

    test "handles {:set, map} for optimistic updates", %{shadow: shadow} do
      s = Shadow.apply_event(shadow, {:set, %{power: true, brightness: 50}})
      assert s.power == true
      assert s.brightness == 50
    end
  end
end
