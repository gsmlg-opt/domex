defmodule Domex.Protocol.Yeelight do
  @moduledoc """
  Sans-I/O codec for Yeelight smart lighting devices.

  Handles:
  - CRLF framing and JSON-RPC encoding/decoding.
  - Command call generation (`encode_call/3`).
  - Parsing incoming frames into response, error, or notification tuples.
  - Parsing SSDP discovery packets.
  """

  @crlf "\r\n"

  @doc """
  Encodes a JSON-RPC command call with CRLF terminator.

  ## Examples

      iex> Domex.Protocol.Yeelight.encode_call(1, "set_power", ["on", "smooth", 500])
      "{\\"id\\":1,\\"method\\":\\"set_power\\",\\"params\\":[\\"on\\",\\"smooth\\",500]}\\r\\n"
  """
  @spec encode_call(pos_integer(), String.t(), list()) :: binary()
  def encode_call(id, method, params \\ [])
      when is_integer(id) and is_binary(method) and is_list(params) do
    payload = %{
      id: id,
      method: method,
      params: params
    }

    Jason.encode_to_iodata!(payload)
    |> IO.iodata_to_binary()
    |> Kernel.<>(@crlf)
  end

  @doc """
  Splits and decodes all complete CRLF-terminated JSON frames from `buffer`.
  Returns `{:ok, decoded_frames, remaining_binary}` or `{:error, reason, remaining_binary}`.

  Each decoded frame is classified into:
  - `{:response, id, result}`
  - `{:error_response, id, error}`
  - `{:props, params}`
  - `{:notification, method, params}`
  - `{:unknown, map}`
  """
  @spec decode_frames(binary()) :: {:ok, list(), binary()}
  def decode_frames(buffer) when is_binary(buffer) do
    do_decode_frames(buffer, [])
  end

  defp do_decode_frames(buffer, acc) do
    case :binary.split(buffer, @crlf) do
      [complete_line, rest] ->
        trimmed = String.trim(complete_line)

        if trimmed == "" do
          do_decode_frames(rest, acc)
        else
          case Jason.decode(trimmed) do
            {:ok, parsed} ->
              classified = classify_frame(parsed)
              do_decode_frames(rest, [classified | acc])

            {:error, _} ->
              # Discard malformed JSON line cleanly and continue with rest
              do_decode_frames(rest, acc)
          end
        end

      [incomplete] ->
        {:ok, Enum.reverse(acc), incomplete}
    end
  end

  @doc """
  Classifies a parsed JSON-RPC map into structured tuple.
  """
  @spec classify_frame(map()) ::
          {:response, pos_integer(), term()}
          | {:error_response, pos_integer(), term()}
          | {:props, map()}
          | {:notification, String.t(), list() | map()}
          | {:unknown, map()}
  def classify_frame(%{"id" => id, "result" => result}) do
    {:response, id, result}
  end

  def classify_frame(%{"id" => id, "error" => error}) do
    {:error_response, id, error}
  end

  def classify_frame(%{"method" => "props", "params" => params}) when is_map(params) do
    {:props, params}
  end

  def classify_frame(%{"method" => method, "params" => params}) do
    {:notification, method, params}
  end

  def classify_frame(other) when is_map(other) do
    {:unknown, other}
  end

  @doc """
  Parses a Yeelight SSDP announcement or discovery response packet.

  Extracts headers:
  - `id`: unique device ID (e.g. "0x0000000003...")
  - `location`: "yeelight://IP:PORT"
  - `host` & `port`: extracted from location
  - `model`: device model (e.g. "color", "mono", "ceiling")
  - `power`: "on" or "off"
  - `bright`: integer 1-100
  - `color_mode`: 1 (rgb), 2 (color_temp), 3 (hsv)
  - `ct`: color temperature (1700-6500)
  - `rgb`: integer RGB value
  - `support`: list of supported command method names
  - `name`: friendly device name
  """
  @spec parse_advertisement(binary()) :: {:ok, map()} | {:error, :not_yeelight}
  def parse_advertisement(packet) when is_binary(packet) do
    lines = String.split(packet, ~r/\r?\n/)

    headers =
      Enum.reduce(lines, %{}, fn line, acc ->
        case String.split(line, ":", parts: 2) do
          [key, value] ->
            Map.put(acc, String.downcase(String.trim(key)), String.trim(value))

          _ ->
            acc
        end
      end)

    case Map.get(headers, "location") do
      "yeelight://" <> location_rest ->
        {host, port} = parse_location(location_rest)

        parsed = %{
          id: Map.get(headers, "id"),
          location: Map.get(headers, "location"),
          host: host,
          port: port,
          model: Map.get(headers, "model"),
          power: Map.get(headers, "power"),
          bright: parse_int(Map.get(headers, "bright")),
          color_mode: parse_int(Map.get(headers, "color_mode")),
          ct: parse_int(Map.get(headers, "ct")),
          rgb: parse_int(Map.get(headers, "rgb")),
          hue: parse_int(Map.get(headers, "hue")),
          sat: parse_int(Map.get(headers, "sat")),
          name: Map.get(headers, "name", ""),
          support: parse_support(Map.get(headers, "support", ""))
        }

        {:ok, parsed}

      _ ->
        {:error, :not_yeelight}
    end
  end

  defp parse_location(loc) do
    case String.split(loc, ":") do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, _} -> {host, port}
          :error -> {host, 55443}
        end

      [host] ->
        {host, 55443}
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_support(str) do
    str
    |> String.split(~r/\s+/, trim: true)
  end
end
