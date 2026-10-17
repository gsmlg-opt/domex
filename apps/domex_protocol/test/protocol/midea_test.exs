defmodule Domex.Protocol.MideaTest do
  use ExUnit.Case, async: true
  alias Domex.Protocol.Midea

  describe "checksum/1 and verify_checksum/1" do
    test "correctly calculates byte checksum" do
      # Example body
      body = <<0x20, 0xAC, 0x00, 0x01, 0x02>>
      ck = Midea.checksum(body)
      frame = <<0xAA, body::binary, ck::8>>

      assert Midea.verify_checksum(frame)
    end

    test "rejects frame with modified body" do
      body = <<0x20, 0xAC, 0x00, 0x01, 0x02>>
      ck = Midea.checksum(body)
      corrupted_frame = <<0xAA, 0x20, 0xAC, 0x00, 0x01, 0x03, ck::8>>

      refute Midea.verify_checksum(corrupted_frame)
    end
  end

  describe "crc8/1" do
    test "computes deterministic CRC-8" do
      assert Midea.crc8(<<0x01, 0x02, 0x03, 0x04>>) == Midea.crc8(<<0x01, 0x02, 0x03, 0x04>>)
      refute Midea.crc8(<<0x01, 0x02, 0x03, 0x04>>) == Midea.crc8(<<0x01, 0x02, 0x03, 0x05>>)
    end
  end

  describe "validate_frame/1" do
    test "recognizes 0x5A5A (V2) frames" do
      packet = <<0x5A, 0x5A, 0x00, 0x08, 0x01, 0x02, 0x03, 0x04>>
      assert {:ok, :v2, 8, <<0x01, 0x02, 0x03, 0x04>>} = Midea.validate_frame(packet)
    end

    test "recognizes 0x8370 (V3) frames" do
      packet = <<0x83, 0x70, 0x00, 0x08, 0x05, 0x06, 0x07, 0x08>>
      assert {:ok, :v3, 8, <<0x05, 0x06, 0x07, 0x08>>} = Midea.validate_frame(packet)
    end

    test "recognizes and validates 0xAA appliance frames" do
      query = Midea.encode_query()
      expected_len = byte_size(query)
      assert {:ok, :appliance, ^expected_len, _rest} = Midea.validate_frame(query)
    end

    test "handles incomplete frame" do
      assert {:error, :incomplete} = Midea.validate_frame(<<0x83, 0x70, 0x00, 0x10>>)
    end

    test "rejects invalid header" do
      assert {:error, :invalid_header} = Midea.validate_frame(<<0x11, 0x22, 0x33, 0x44>>)
    end
  end

  describe "encode_query/1 and parse_appliance_frame/1" do
    test "encodes query frame with correct checksum" do
      frame = Midea.encode_query()
      assert byte_size(frame) == 33
      assert <<0xAA, 0x20, 0xAC, _::binary>> = frame
      assert Midea.verify_checksum(frame)
    end

    test "encodes control command and roundtrips parsed state" do
      control =
        Midea.encode_control(%{
          power: true,
          target_temp: 25.5,
          mode: :cool,
          fan_speed: :high,
          swing_vertical: true,
          swing_horizontal: false
        })

      assert byte_size(control) == 33
      assert Midea.verify_checksum(control)

      # Now parse this frame as an appliance frame
      assert {:ok, state} = Midea.parse_appliance_frame(control)
      assert state.appliance_type == 0xAC
      assert state.message_type == :control
      assert state.power == true
      assert state.target_temp == 25.5
      assert state.mode == :cool
      assert state.fan_speed == :high
      assert state.swing_vertical == true
      assert state.swing_horizontal == false
    end

    test "parses AC status response with indoor and outdoor temperatures" do
      # Mock a status response (0x02)
      # 24 deg C, cool, auto fan, indoor 26.5 deg C (103 -> (103-50)/2 = 26.5)
      # outdoor 32 deg C (114 -> (114-50)/2 = 32.0)
      payload =
        <<0x11, 0x40, 102, 0x00, 0, 0, 0, 0, 0, 0, 0, 103, 114, 0, 0, 0, 0, 0, 0, 0, 0>>

      body = <<0x20::8, 0xAC::8, 0, 0, 0, 0, 0, 0, 0x03::8, 0x02::8, payload::binary>>
      ck = Midea.checksum(body)
      frame = <<0xAA, body::binary, ck::8>>

      assert {:ok, parsed} = Midea.parse_appliance_frame(frame)
      assert parsed.message_type == :status_response
      assert parsed.power == true
      assert parsed.target_temp == 24.0
      assert parsed.mode == :cool
      assert parsed.fan_speed == :auto
      assert parsed.indoor_temp == 26.5
      assert parsed.outdoor_temp == 32.0
    end
  end
end
