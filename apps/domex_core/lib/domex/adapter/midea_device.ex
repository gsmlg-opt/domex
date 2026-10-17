defmodule Domex.Adapter.MideaDevice do
  @moduledoc """
  Adapter for Midea smart appliances (AC, Heat Pumps) over LAN TCP (port 6444).
  """

  use Domex.Adapter.Behaviour
  alias Domex.Protocol.Midea

  @default_port 6444

  defstruct [
    :host,
    :port,
    :req_id,
    buffer: "",
    last_ac_state: %{
      power: false,
      target_temp: 24.0,
      mode: :cool,
      fan_speed: :auto,
      swing_vertical: false,
      swing_horizontal: false
    }
  ]

  @impl true
  def transport, do: :tcp

  @impl true
  def default_port, do: @default_port

  @impl true
  def init(config) do
    host = Map.get(config, :host) || Map.get(config, "host")
    port = Map.get(config, :port) || Map.get(config, "port") || @default_port

    if is_nil(host) do
      {:error, :missing_host}
    else
      state = %__MODULE__{
        host: host,
        port: port,
        req_id: 1,
        buffer: ""
      }

      {:ok, state}
    end
  end

  @impl true
  def connect_opts(%__MODULE__{host: host, port: port}) do
    formatted_host =
      if is_binary(host) do
        String.to_charlist(host)
      else
        host
      end

    {:ok, formatted_host, port, [:binary, packet: :raw, active: :once]}
  end

  @impl true
  def handle_connected(state) do
    query = Midea.encode_query()
    {:ok, [query], state}
  end

  @impl true
  def handle_data(raw_binary, %__MODULE__{buffer: buffer} = state) do
    combined = buffer <> raw_binary
    {frames, remaining} = extract_frames(combined, [])

    {events, replies, updated_ac_state} =
      Enum.reduce(frames, {[], [], state.last_ac_state}, fn frame, {ev_acc, rep_acc, ac_acc} ->
        case Midea.parse_appliance_frame(frame) do
          {:ok, parsed} ->
            new_ac = Map.merge(ac_acc, parsed)
            ev = {:state, new_ac}
            rep = {state.req_id - 1, {:ok, new_ac}}
            {[ev | ev_acc], [rep | rep_acc], new_ac}

          {:error, _} ->
            {ev_acc, rep_acc, ac_acc}
        end
      end)

    {:ok, Enum.reverse(events), Enum.reverse(replies),
     %{state | buffer: remaining, last_ac_state: updated_ac_state}}
  end

  @impl true
  def encode_command(command, args, %__MODULE__{req_id: id} = state) do
    {packet, new_ac_state} = build_command(command, args, state.last_ac_state)
    {:ok, packet, id, %{state | req_id: id + 1, last_ac_state: new_ac_state}}
  end

  @impl true
  def poll(state) do
    query = Midea.encode_query()
    {:ok, [query], state}
  end

  defp extract_frames(<<>>, acc), do: {Enum.reverse(acc), <<>>}

  defp extract_frames(buffer, acc) do
    case Midea.validate_frame(buffer) do
      {:ok, :appliance, frame_len, _rest} ->
        <<frame::binary-size(frame_len), remaining::binary>> = buffer
        extract_frames(remaining, [frame | acc])

      {:ok, type, packet_len, _rest} when type in [:v2, :v3] ->
        # For v2/v3 outer packet, if it encapsulates 0xAA, unpack or advance
        <<_outer::binary-size(packet_len), remaining::binary>> = buffer
        extract_frames(remaining, acc)

      {:error, :incomplete} ->
        {Enum.reverse(acc), buffer}

      {:error, _} ->
        # Skip 1 malformed byte to regain sync
        <<_skip::8, rest::binary>> = buffer
        extract_frames(rest, acc)
    end
  end

  defp build_command(:query, _args, current_ac) do
    {Midea.encode_query(), current_ac}
  end

  defp build_command(:set_power, [bool], current_ac) when is_boolean(bool) do
    new_ac = %{current_ac | power: bool}
    {Midea.encode_control(new_ac), new_ac}
  end

  defp build_command(:set_power, bool, current_ac) when is_boolean(bool),
    do: build_command(:set_power, [bool], current_ac)

  defp build_command(:set_temp, [temp], current_ac) when is_number(temp) do
    new_ac = %{current_ac | target_temp: temp * 1.0}
    {Midea.encode_control(new_ac), new_ac}
  end

  defp build_command(:set_temp, temp, current_ac) when is_number(temp),
    do: build_command(:set_temp, [temp], current_ac)

  defp build_command(:set_mode, [mode], current_ac) when is_atom(mode) do
    new_ac = %{current_ac | mode: mode}
    {Midea.encode_control(new_ac), new_ac}
  end

  defp build_command(:set_mode, mode, current_ac) when is_atom(mode),
    do: build_command(:set_mode, [mode], current_ac)

  defp build_command(:set_fan_speed, [speed], current_ac) when is_atom(speed) do
    new_ac = %{current_ac | fan_speed: speed}
    {Midea.encode_control(new_ac), new_ac}
  end

  defp build_command(:set_fan_speed, speed, current_ac) when is_atom(speed),
    do: build_command(:set_fan_speed, [speed], current_ac)

  defp build_command(:control, attrs, current_ac) when is_map(attrs) do
    new_ac = Map.merge(current_ac, attrs)
    {Midea.encode_control(new_ac), new_ac}
  end

  defp build_command(_other, _args, current_ac) do
    {Midea.encode_query(), current_ac}
  end
end
