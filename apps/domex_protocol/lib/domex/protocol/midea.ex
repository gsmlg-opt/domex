defmodule Domex.Protocol.Midea do
  @moduledoc """
  Sans-I/O codec for Midea smart appliances (Air Conditioners, Heat Pumps, etc.).

  Handles:
  - Header & framing validation for `0x5A5A` (V2), `0x8370` (V3), and `0xAA` (appliance frames).
  - Byte checksum and CRC calculations.
  - Appliance payload parsing (AC target temp, indoor/outdoor temp, power, operational mode, fan speed, swing).
  - Command encoding for query (`0x41`) and control (`0x40`).
  """

  import Bitwise

  @magic_v2 0x5A5A
  @magic_v3 0x8370
  @header_aa 0xAA
  @appliance_ac 0xAC

  # Command / Message Types
  @cmd_control 0x40
  @cmd_query 0x41
  @msg_status_resp 0x02
  @msg_state_change 0x03

  # Modes
  @mode_auto 1
  @mode_cool 2
  @mode_dry 3
  @mode_heat 4
  @mode_fan 5

  # Fan Speeds
  @fan_silent 20
  @fan_low 40
  @fan_medium 60
  @fan_high 80
  @fan_auto 102

  @doc """
  Validates and classifies an incoming binary packet.
  Identifies `0x5A5A`, `0x8370`, or `0xAA` frames.
  """
  @spec validate_frame(binary()) ::
          {:ok, :v2, pos_integer(), binary()}
          | {:ok, :v3, pos_integer(), binary()}
          | {:ok, :appliance, pos_integer(), binary()}
          | {:error, :incomplete | :invalid_header}
  def validate_frame(<<@magic_v2::16, length::16, rest::binary>> = data) do
    if byte_size(data) >= length do
      {:ok, :v2, length, rest}
    else
      {:error, :incomplete}
    end
  end

  def validate_frame(<<@magic_v3::16, length::16, rest::binary>> = data) do
    if byte_size(data) >= length do
      {:ok, :v3, length, rest}
    else
      {:error, :incomplete}
    end
  end

  def validate_frame(<<@header_aa, length::8, rest::binary>> = data) do
    # 0xAA frame: length is byte size of frame excluding header byte 0xAA,
    # or total length = length + 1.
    total_len = length + 1

    cond do
      byte_size(data) < total_len ->
        {:error, :incomplete}

      true ->
        <<frame_bytes::binary-size(^total_len), _remaining::binary>> = data

        if verify_checksum(frame_bytes) do
          {:ok, :appliance, total_len, rest}
        else
          {:error, :invalid_checksum}
        end
    end
  end

  def validate_frame(data) when byte_size(data) < 4, do: {:error, :incomplete}
  def validate_frame(_), do: {:error, :invalid_header}

  @doc """
  Calculates the standard Midea byte checksum.
  Checksum = (256 - sum(bytes) % 256) & 0xFF
  """
  @spec checksum(binary()) :: byte()
  def checksum(bytes) when is_binary(bytes) do
    sum = :erlang.binary_to_list(bytes) |> Enum.sum()
    band(256 - rem(sum, 256), 0xFF)
  end

  @doc """
  Verifies the byte checksum of a complete 0xAA frame.
  The checksum is the last byte of the frame covering bytes from index 1 to len - 2.
  """
  @spec verify_checksum(binary()) :: boolean()
  def verify_checksum(<<_header::8, body_and_checksum::binary>>)
      when byte_size(body_and_checksum) >= 2 do
    body_len = byte_size(body_and_checksum) - 1
    <<body::binary-size(^body_len), expected_checksum::8>> = body_and_checksum
    checksum(body) == expected_checksum
  end

  def verify_checksum(_), do: false

  @doc """
  Calculates standard CRC-8 (polynomial 0x31, init 0x00).
  """
  @spec crc8(binary()) :: byte()
  def crc8(data) when is_binary(data) do
    for <<byte <- data>>, reduce: 0 do
      crc ->
        Enum.reduce(0..7, bxor(crc, byte), fn _, acc ->
          if band(acc, 0x80) != 0 do
            bxor(band(acc <<< 1, 0xFF), 0x31)
          else
            band(acc <<< 1, 0xFF)
          end
        end)
    end
  end

  @doc """
  Parses a complete 0xAA appliance frame.
  Extracts appliance type, message type, and detailed AC status if type is 0xAC.
  """
  @spec parse_appliance_frame(binary()) :: {:ok, map()} | {:error, term()}
  def parse_appliance_frame(
        <<@header_aa, length::8, appliance_type::8, _sync::48, subtype::8, message_type::8,
          payload_and_checksum::binary>>
      ) do
    payload_len = length - 11

    if byte_size(payload_and_checksum) < payload_len + 1 do
      {:error, :incomplete_payload}
    else
      <<payload::binary-size(^payload_len), _checksum::8, _rest::binary>> = payload_and_checksum

      parsed = %{
        appliance_type: appliance_type,
        subtype: subtype,
        message_type: decode_message_type(message_type),
        raw_message_type: message_type
      }

      case appliance_type do
        @appliance_ac ->
          ac_state = parse_ac_payload(payload)
          {:ok, Map.merge(parsed, ac_state)}

        _ ->
          {:ok, Map.put(parsed, :raw_payload, payload)}
      end
    end
  end

  def parse_appliance_frame(_), do: {:error, :invalid_appliance_frame}

  @doc """
  Parses Midea AC payload bytes into structured state map.
  """
  @spec parse_ac_payload(binary()) :: map()
  def parse_ac_payload(payload) when byte_size(payload) >= 12 do
    bytes = :erlang.binary_to_list(payload)

    # Byte 0: Power, Target Temp Integer
    b0 = Enum.at(bytes, 0)
    power = band(b0, 0x01) == 0x01
    target_temp_int = band(b0 >>> 1, 0x0F) + 16

    # Byte 1: Mode
    b1 = Enum.at(bytes, 1)
    mode_raw = band(b1 >>> 5, 0x07)
    mode = decode_mode(mode_raw)

    # Byte 2: Fan Speed
    b2 = Enum.at(bytes, 2)
    fan_speed_raw = band(b2, 0x7F)
    fan_speed = decode_fan_speed(fan_speed_raw)

    # Byte 3: Swing
    b3 = Enum.at(bytes, 3)
    swing_vertical = band(b3, 0x0C) != 0
    swing_horizontal = band(b3, 0x03) != 0

    # Optional fractional temp in Byte 1 (bit 4) or Byte 12
    # In Midea AC: bit 4 of byte 1 is 0.5 deg C offset
    half_temp = if band(b1, 0x10) != 0, do: 0.5, else: 0.0
    target_temp = target_temp_int + half_temp

    # Indoor / Outdoor temperature (if available, usually bytes 11 & 12)
    indoor_temp =
      if length(bytes) > 11 do
        b11 = Enum.at(bytes, 11)
        if b11 > 0, do: (b11 - 50) / 2.0, else: nil
      else
        nil
      end

    outdoor_temp =
      if length(bytes) > 12 do
        b12 = Enum.at(bytes, 12)
        if b12 > 0, do: (b12 - 50) / 2.0, else: nil
      else
        nil
      end

    %{
      power: power,
      target_temp: target_temp,
      mode: mode,
      fan_speed: fan_speed,
      swing_vertical: swing_vertical,
      swing_horizontal: swing_horizontal,
      indoor_temp: indoor_temp,
      outdoor_temp: outdoor_temp
    }
  end

  def parse_ac_payload(_), do: %{}

  @doc """
  Builds a query status command frame (`0x41`) for Midea AC.
  """
  @spec encode_query(byte()) :: binary()
  def encode_query(appliance_type \\ @appliance_ac) do
    # Standard 0xAA query frame length is 0x20 (32 bytes excluding 0xAA)
    # Header: AA 20 AC 00 00 00 00 00 00 03 41 ...
    body =
      <<0x20::8, appliance_type::8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03::8, @cmd_query::8,
        0x81, 0x00, 0xFF, 0x03, 0xFF, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>

    ck = checksum(body)
    <<@header_aa, body::binary, ck::8>>
  end

  @doc """
  Builds a control command frame (`0x40`) for Midea AC.

  Options:
  - `:power` -> boolean
  - `:target_temp` -> number (16..30)
  - `:mode` -> `:auto | :cool | :dry | :heat | :fan`
  - `:fan_speed` -> `:auto | :silent | :low | :medium | :high`
  - `:swing_vertical` -> boolean
  - `:swing_horizontal` -> boolean
  """
  @spec encode_control(map()) :: binary()
  def encode_control(attrs) when is_map(attrs) do
    power_bit = if Map.get(attrs, :power, true), do: 0x01, else: 0x00

    target_temp = Map.get(attrs, :target_temp, 24)
    target_temp_clamped = max(16.0, min(30.0, target_temp * 1.0))
    temp_int = trunc(target_temp_clamped) - 16
    temp_half = if target_temp_clamped - trunc(target_temp_clamped) >= 0.5, do: 0x10, else: 0x00

    mode = Map.get(attrs, :mode, :cool)
    mode_code = encode_mode(mode)
    b1 = bor(band(mode_code <<< 5, 0xE0), temp_half)

    b0 = bor(band(temp_int <<< 1, 0x1E), power_bit)

    fan_speed = Map.get(attrs, :fan_speed, :auto)
    b2 = encode_fan_speed(fan_speed)

    swing_v = if Map.get(attrs, :swing_vertical, false), do: 0x0C, else: 0x00
    swing_h = if Map.get(attrs, :swing_horizontal, false), do: 0x03, else: 0x00
    b3 = bor(swing_v, swing_h)

    payload =
      <<b0::8, b1::8, b2::8, b3::8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>

    # Total frame size = 1 (AA) + 1 (len) + 1 (type) + 6 (sync) + 1 (subtype) + 1 (cmd) + payload + 1 (ck)
    # len = 10 + byte_size(payload) = 32
    body =
      <<0x20::8, @appliance_ac::8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03::8, @cmd_control::8,
        payload::binary>>

    ck = checksum(body)
    <<@header_aa, body::binary, ck::8>>
  end

  defp decode_message_type(@cmd_query), do: :query
  defp decode_message_type(@cmd_control), do: :control
  defp decode_message_type(@msg_status_resp), do: :status_response
  defp decode_message_type(@msg_state_change), do: :state_change
  defp decode_message_type(other), do: {:unknown, other}

  defp decode_mode(@mode_auto), do: :auto
  defp decode_mode(@mode_cool), do: :cool
  defp decode_mode(@mode_dry), do: :dry
  defp decode_mode(@mode_heat), do: :heat
  defp decode_mode(@mode_fan), do: :fan
  defp decode_mode(_), do: :cool

  defp encode_mode(:auto), do: @mode_auto
  defp encode_mode(:cool), do: @mode_cool
  defp encode_mode(:dry), do: @mode_dry
  defp encode_mode(:heat), do: @mode_heat
  defp encode_mode(:fan), do: @mode_fan
  defp encode_mode(_), do: @mode_cool

  defp decode_fan_speed(speed) when speed >= 100, do: :auto
  defp decode_fan_speed(speed) when speed >= 80, do: :high
  defp decode_fan_speed(speed) when speed >= 60, do: :medium
  defp decode_fan_speed(speed) when speed >= 40, do: :low
  defp decode_fan_speed(speed) when speed >= 20, do: :silent
  defp decode_fan_speed(_), do: :auto

  defp encode_fan_speed(:silent), do: @fan_silent
  defp encode_fan_speed(:low), do: @fan_low
  defp encode_fan_speed(:medium), do: @fan_medium
  defp encode_fan_speed(:high), do: @fan_high
  defp encode_fan_speed(_), do: @fan_auto
end
