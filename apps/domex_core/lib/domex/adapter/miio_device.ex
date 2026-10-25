defmodule Domex.Adapter.MiioDevice do
  @moduledoc """
  Adapter for Xiaomi miIO & MIoT smart devices over LAN UDP (port 54321).

  Handles stamp synchronization, cryptographic key derivation, and MIoT property mapping.
  """

  use Domex.Adapter.Behaviour
  alias Domex.Protocol.Miio
  alias Domex.Protocol.MiioSpec

  @default_port 54321

  defstruct [
    :host,
    :port,
    :token,
    :did,
    :stamp,
    :stamp_synced_at,
    :req_id,
    :profile
  ]

  @impl true
  def transport, do: :udp

  @impl true
  def default_port, do: @default_port

  @impl true
  def init(config) do
    host = Map.get(config, :host) || Map.get(config, "host")
    port = Map.get(config, :port) || Map.get(config, "port") || @default_port
    token = Map.get(config, :token) || Map.get(config, "token")
    did = parse_did(Map.get(config, :did) || Map.get(config, "did"))
    profile = Map.get(config, :profile) || Map.get(config, "profile") || :switch

    if is_nil(host) or is_nil(token) do
      {:error, :missing_host_or_token}
    else
      state = %__MODULE__{
        host: host,
        port: port,
        token: token,
        did: did,
        stamp: 0,
        stamp_synced_at: System.monotonic_time(:second),
        req_id: 1,
        profile: profile
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

    {:ok, formatted_host, port, [:binary, active: :once]}
  end

  @impl true
  def handle_connected(state) do
    # On connect, immediately send Hello to synchronize stamp and discover did
    hello_packet = Miio.hello()
    {:ok, [hello_packet], state}
  end

  @impl true
  def handle_data(raw_binary, state) do
    cond do
      byte_size(raw_binary) == 32 ->
        case Miio.decode_hello(raw_binary) do
          {:ok, %{did: did, stamp: stamp}} ->
            new_did = if state.did == 0, do: did, else: state.did

            new_state = %{
              state
              | did: new_did,
                stamp: stamp,
                stamp_synced_at: System.monotonic_time(:second)
            }

            events = [{:online, true}]
            {:ok, events, [], new_state}

          {:error, _} ->
            {:ok, [], [], state}
        end

      true ->
        case Miio.decode_packet(raw_binary, state.token) do
          {:ok, %{stamp: stamp, payload: payload}} ->
            new_state = %{
              state
              | stamp: max(state.stamp, stamp),
                stamp_synced_at: System.monotonic_time(:second)
            }

            {events, replies} = process_payload(payload, new_state)
            {:ok, events, replies, new_state}

          {:error, _reason} ->
            {:ok, [], [], state}
        end
    end
  end

  @impl true
  def encode_command(command, args, %__MODULE__{req_id: id} = state) do
    current_stamp = next_stamp(state)
    payload = build_command_payload(command, args, id, state)

    packet = Miio.encode_packet(state.did, current_stamp, state.token, payload)
    new_state = %{state | req_id: id + 1, stamp: current_stamp}

    {:ok, packet, id, new_state}
  end

  @impl true
  def poll(state) do
    # Periodic Hello packet to maintain stamp synchronization
    hello = Miio.hello()
    {:ok, [hello], state}
  end

  defp next_stamp(state) do
    elapsed = System.monotonic_time(:second) - state.stamp_synced_at
    state.stamp + max(1, elapsed)
  end

  defp build_command_payload(:set_power, [bool_or_str], id, state) do
    val = bool_or_str in [true, "on", 1]

    case state.profile do
      :miot_light ->
        MiioSpec.set_property(id, state.did, 2, 1, val)

      :miot_switch ->
        MiioSpec.set_property(id, state.did, 2, 1, val)

      _ ->
        # Standard miIO RPC
        %{"id" => id, "method" => "set_power", "params" => [if(val, do: "on", else: "off")]}
    end
  end

  defp build_command_payload(:set_power, val, id, state),
    do: build_command_payload(:set_power, [val], id, state)

  defp build_command_payload(:set_brightness, [val], id, state) do
    int_val = if is_integer(val), do: val, else: String.to_integer(to_string(val))

    case state.profile do
      :miot_light ->
        MiioSpec.set_property(id, state.did, 2, 2, int_val)

      _ ->
        %{"id" => id, "method" => "set_bright", "params" => [int_val]}
    end
  end

  defp build_command_payload(:set_brightness, val, id, state),
    do: build_command_payload(:set_brightness, [val], id, state)

  defp build_command_payload(:get_properties, specs, id, state) when is_list(specs) do
    MiioSpec.get_properties(id, state.did, specs)
  end

  defp build_command_payload(method, params, id, _state) when is_list(params) do
    %{"id" => id, "method" => to_string(method), "params" => params}
  end

  defp build_command_payload(method, param, id, state),
    do: build_command_payload(method, [param], id, state)

  defp process_payload(%{"id" => id, "result" => result}, state) do
    rep = {id, {:ok, result}}

    events =
      cond do
        is_list(result) and match_miot_results?(result) ->
          schema =
            case state.profile do
              :miot_light -> MiioSpec.light_profile()
              _ -> MiioSpec.plug_profile()
            end

          props = MiioSpec.map_named_properties(result, schema)
          [{:props, props}]

        is_list(result) and result in [["on"], ["off"]] ->
          [val] = result
          [{:props, %{power: val == "on"}}]

        true ->
          []
      end

    {events, [rep]}
  end

  defp process_payload(%{"id" => id, "error" => error}, _state) do
    {[], [{id, {:error, error}}]}
  end

  defp process_payload(_other, _state) do
    {[], []}
  end

  defp match_miot_results?([%{"siid" => _, "piid" => _} | _]), do: true
  defp match_miot_results?(_), do: false

  defp parse_did(nil), do: 0
  defp parse_did(did) when is_integer(did), do: did

  defp parse_did(did) when is_binary(did) do
    case Integer.parse(did) do
      {int, _} -> int
      :error -> 0
    end
  end
end
