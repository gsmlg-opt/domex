defmodule Domex.Discovery.MiioProbe do
  @moduledoc """
  UDP 54321 discovery probe for Xiaomi miIO devices.
  Sends Hello packets to broadcast or targeted IPs and listens for 32-byte responses.
  """

  use GenServer
  require Logger

  alias Domex.Protocol.Miio
  alias Domex.PubSub

  @miio_port 54321

  defstruct [:socket]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a Hello probe to a specific host IP.
  """
  def probe(host) do
    GenServer.cast(__MODULE__, {:probe, host})
  end

  @doc """
  Sends a Hello broadcast to discover local devices.
  """
  def sweep(broadcast_ip \\ "255.255.255.255") do
    GenServer.cast(__MODULE__, {:sweep, broadcast_ip})
  end

  @impl true
  def init(_opts) do
    udp_opts = [:binary, active: true, broadcast: true, reuseaddr: true]

    case :gen_udp.open(0, udp_opts) do
      {:ok, socket} ->
        {:ok, %__MODULE__{socket: socket}}

      {:error, reason} ->
        Logger.warning(
          "[Domex.Discovery.MiioProbe] Failed to open UDP socket: #{inspect(reason)}"
        )

        {:ok, %__MODULE__{socket: nil}}
    end
  end

  @impl true
  def handle_cast({:probe, host}, %{socket: socket} = state) when not is_nil(socket) do
    packet = Miio.hello()
    formatted_host = if is_binary(host), do: String.to_charlist(host), else: host
    :gen_udp.send(socket, formatted_host, @miio_port, packet)
    {:noreply, state}
  end

  def handle_cast({:sweep, broadcast_ip}, %{socket: socket} = state) when not is_nil(socket) do
    packet = Miio.hello()
    target = if is_binary(broadcast_ip), do: String.to_charlist(broadcast_ip), else: broadcast_ip
    :gen_udp.send(socket, target, @miio_port, packet)
    {:noreply, state}
  end

  def handle_cast(_other, state), do: {:noreply, state}

  @impl true
  def handle_info({:udp, _socket, ip, _port, data}, state) when byte_size(data) == 32 do
    case Miio.decode_hello(data) do
      {:ok, %{did: did, stamp: stamp}} ->
        host_str = format_ip(ip)

        discovered = %{
          id: "miio_#{did}",
          name: "Xiaomi Device #{did}",
          type: :switch,
          adapter: Domex.Adapter.MiioDevice,
          host: host_str,
          port: @miio_port,
          did: did,
          metadata: %{did: did, stamp: stamp}
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
