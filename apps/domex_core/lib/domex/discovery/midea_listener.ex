defmodule Domex.Discovery.MideaListener do
  @moduledoc """
  UDP 6445 broadcast listener and discovery prober for Midea smart appliances.
  """

  use GenServer
  require Logger

  alias Domex.Protocol.Midea
  alias Domex.PubSub

  @midea_udp_port 6445

  defstruct [:socket]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Broadcasts a discovery query for Midea appliances.
  """
  def probe(broadcast_ip \\ "255.255.255.255") do
    GenServer.cast(__MODULE__, {:probe, broadcast_ip})
  end

  @impl true
  def init(_opts) do
    udp_opts = [:binary, active: true, broadcast: true, reuseaddr: true]

    # Try binding to 6445 or ephemeral port if 6445 is occupied
    case :gen_udp.open(@midea_udp_port, udp_opts) do
      {:ok, socket} ->
        Logger.info("[Domex.Discovery.MideaListener] Listening on UDP #{@midea_udp_port}")
        {:ok, %__MODULE__{socket: socket}}

      {:error, _} ->
        case :gen_udp.open(0, udp_opts) do
          {:ok, socket} ->
            {:ok, %__MODULE__{socket: socket}}

          {:error, reason} ->
            Logger.warning(
              "[Domex.Discovery.MideaListener] Failed to open UDP socket: #{inspect(reason)}"
            )

            {:ok, %__MODULE__{socket: nil}}
        end
    end
  end

  @impl true
  def handle_cast({:probe, target_ip}, %{socket: socket} = state) when not is_nil(socket) do
    query = Midea.encode_query()
    target = if is_binary(target_ip), do: String.to_charlist(target_ip), else: target_ip
    :gen_udp.send(socket, target, @midea_udp_port, query)
    {:noreply, state}
  end

  def handle_cast(_other, state), do: {:noreply, state}

  @impl true
  def handle_info({:udp, _socket, ip, _port, data}, state) do
    case Midea.validate_frame(data) do
      {:ok, :appliance, _len, _} ->
        case Midea.parse_appliance_frame(data) do
          {:ok, %{appliance_type: 0xAC} = parsed} ->
            host_str = format_ip(ip)

            discovered = %{
              id: "midea_ac_#{host_str}",
              name: "Midea Air Conditioner (#{host_str})",
              type: :climate,
              adapter: Domex.Adapter.MideaDevice,
              host: host_str,
              port: 6444,
              metadata: parsed
            }

            PubSub.broadcast_discovery(discovered)

          _ ->
            :ignore
        end

      _ ->
        :ignore
    end

    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{socket: socket}) when not is_nil(socket) do
    :gen_udp.close(socket)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(other), do: to_string(other)
end
