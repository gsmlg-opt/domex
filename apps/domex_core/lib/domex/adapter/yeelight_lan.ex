defmodule Domex.Adapter.YeelightLan do
  @moduledoc """
  Adapter for Yeelight smart lighting devices over LAN TCP (port 55443).
  """

  use Domex.Adapter.Behaviour
  alias Domex.Protocol.Yeelight

  @default_port 55443
  @query_props ["power", "bright", "ct", "rgb", "color_mode", "name"]

  defstruct [:host, :port, :req_id, buffer: ""]

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
  def handle_connected(%__MODULE__{req_id: id} = state) do
    query = Yeelight.encode_call(id, "get_prop", @query_props)
    {:ok, [query], %{state | req_id: id + 1}}
  end

  @impl true
  def handle_data(raw_binary, %__MODULE__{buffer: buffer} = state) do
    combined = buffer <> raw_binary
    {:ok, frames, remaining} = Yeelight.decode_frames(combined)

    {events, replies} =
      Enum.reduce(frames, {[], []}, fn frame, {ev_acc, rep_acc} ->
        case frame do
          {:response, id, result} ->
            rep = {id, {:ok, result}}

            # If result is list matching @query_props length, extract properties
            extra_events =
              if is_list(result) and length(result) == length(@query_props) do
                props =
                  Enum.zip(@query_props, result)
                  |> Enum.reject(fn {_, v} -> v == "" or is_nil(v) end)
                  |> Map.new()

                [{:props, props}]
              else
                []
              end

            {extra_events ++ ev_acc, [rep | rep_acc]}

          {:error_response, id, error} ->
            {ev_acc, [{id, {:error, error}} | rep_acc]}

          {:props, props} ->
            {[{:props, props} | ev_acc], rep_acc}

          {:notification, "props", props} when is_map(props) ->
            {[{:props, props} | ev_acc], rep_acc}

          _other ->
            {ev_acc, rep_acc}
        end
      end)

    {:ok, Enum.reverse(events), Enum.reverse(replies), %{state | buffer: remaining}}
  end

  @impl true
  def encode_command(command, args, %__MODULE__{req_id: id} = state) do
    {method, params} = format_command(command, args)
    encoded = Yeelight.encode_call(id, method, params)
    {:ok, encoded, id, %{state | req_id: id + 1}}
  end

  @impl true
  def poll(%__MODULE__{req_id: id} = state) do
    packet = Yeelight.encode_call(id, "get_prop", @query_props)
    {:ok, [packet], %{state | req_id: id + 1}}
  end

  defp format_command(:set_power, [on_off]) when on_off in ["on", "off"],
    do: {"set_power", [on_off, "smooth", 500]}

  defp format_command(:set_power, true), do: {"set_power", ["on", "smooth", 500]}
  defp format_command(:set_power, false), do: {"set_power", ["off", "smooth", 500]}
  defp format_command("set_power", args), do: format_command(:set_power, args)

  defp format_command(:set_brightness, [val]), do: {"set_bright", [val, "smooth", 500]}

  defp format_command(:set_brightness, val) when is_integer(val),
    do: {"set_bright", [val, "smooth", 500]}

  defp format_command(:set_bright, args), do: format_command(:set_brightness, args)

  defp format_command(:set_color_temp, [val]), do: {"set_ct_abx", [val, "smooth", 500]}

  defp format_command(:set_color_temp, val) when is_integer(val),
    do: {"set_ct_abx", [val, "smooth", 500]}

  defp format_command(:set_ct, args), do: format_command(:set_color_temp, args)

  defp format_command(:set_rgb, [val]), do: {"set_rgb", [val, "smooth", 500]}
  defp format_command(:set_rgb, val) when is_integer(val), do: {"set_rgb", [val, "smooth", 500]}

  defp format_command(:toggle, _), do: {"toggle", []}
  defp format_command("toggle", _), do: {"toggle", []}

  defp format_command(method, params) when is_binary(method) and is_list(params),
    do: {method, params}

  defp format_command(method, params) when is_atom(method) and is_list(params),
    do: {to_string(method), params}

  defp format_command(method, param), do: {to_string(method), [param]}
end
