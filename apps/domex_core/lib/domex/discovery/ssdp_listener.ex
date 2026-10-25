defmodule Domex.Discovery.SsdpListener do
  @moduledoc """
  SSDP UDP multicast listener for discovering Yeelight LAN devices on port 1982.
  """

  use GenServer
  require Logger

  alias Domex.Protocol.Yeelight
  alias Domex.PubSub

  @multicast_addr {239, 255, 255, 250}
  @multicast_port 1982

  defstruct [:socket]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    udp_opts = [
      :binary,
      active: true,
      reuseaddr: true,
      add_membership: {@multicast_addr, {0, 0, 0, 0}}
    ]

    case :gen_udp.open(@multicast_port, udp_opts) do
      {:ok, socket} ->
        Logger.info(
          "[Domex.Discovery.SsdpListener] Listening on UDP #{@multicast_port} multicast"
        )

        {:ok, %__MODULE__{socket: socket}}

      {:error, reason} ->
        Logger.warning(
          "[Domex.Discovery.SsdpListener] Could not bind UDP #{@multicast_port} (#{inspect(reason)}), falling back to passive mode"
        )

        {:ok, %__MODULE__{socket: nil}}
    end
  end

  @impl true
  def handle_info({:udp, _socket, ip, _port, data}, state) do
    case Yeelight.parse_advertisement(data) do
      {:ok, ad} ->
        host = ad.host || format_ip(ip)

        discovered = %{
          id: ad.id || "yeelight_#{host}",
          name: if(ad.name && ad.name != "", do: ad.name, else: "Yeelight #{ad.model || "Bulb"}"),
          type: :light,
          adapter: Domex.Adapter.YeelightLan,
          host: host,
          port: ad.port,
          metadata: ad
        }

        PubSub.broadcast_discovery(discovered)

      {:error, _} ->
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
