defmodule Domex.Device.Session do
  @moduledoc """
  Per-device GenServer managing connection lifecycle, transport I/O,
  stamp synchronization, decoupled RPC queues, and Shadow state replication.
  """

  use GenServer, restart: :transient
  require Logger

  alias Domex.Device.Registry, as: DevRegistry
  alias Domex.Device.Shadow
  alias Domex.PubSub

  @initial_backoff_ms 1_000
  @max_backoff_ms 30_000
  @default_rpc_timeout_ms 3_000
  @default_poll_interval_ms 30_000

  defstruct [
    :id,
    :config,
    :adapter,
    :adapter_state,
    :transport,
    :socket,
    :shadow,
    :dest_host,
    :dest_port,
    status: :disconnected,
    backoff_ms: @initial_backoff_ms,
    reconnect_timer: nil,
    poll_timer: nil,
    rpc_queue: %{}
  ]

  # Client API

  @doc """
  Starts a device session under a registered name.
  """
  def start_link(config) when is_map(config) do
    device_id =
      to_string(
        Map.get(config, :id) || Map.get(config, "id") ||
          "dev_#{:erlang.unique_integer([:positive])}"
      )

    GenServer.start_link(__MODULE__, Map.put(config, :id, device_id),
      name: DevRegistry.via_tuple(device_id)
    )
  end

  @doc """
  Returns the current immutable Shadow struct for the device.
  """
  def get_shadow(server) do
    GenServer.call(to_server(server), :get_shadow)
  end

  @doc """
  Sends a command to the device and waits for the RPC reply.
  """
  def command(server, cmd, args \\ [], timeout \\ @default_rpc_timeout_ms) do
    GenServer.call(to_server(server), {:command, cmd, args, timeout}, timeout + 500)
  end

  @doc """
  Optimistically updates the local Shadow without waiting for device acknowledgement.
  """
  def set_shadow(server, changes) when is_map(changes) do
    GenServer.cast(to_server(server), {:set_shadow, changes})
  end

  # Server Callbacks

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    adapter = Map.get(config, :adapter) || Map.get(config, "adapter")
    adapter = resolve_adapter(adapter)
    device_id = to_string(Map.get(config, :id))

    case adapter.init(config) do
      {:ok, adapter_state} ->
        shadow = Shadow.new(Map.put(config, :adapter, adapter))

        state = %__MODULE__{
          id: device_id,
          config: config,
          adapter: adapter,
          adapter_state: adapter_state,
          transport: adapter.transport(),
          shadow: shadow,
          status: :disconnected,
          backoff_ms: @initial_backoff_ms
        }

        # Connect asynchronously in continue to keep init fast
        {:ok, state, {:continue, :connect}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    {:noreply, attempt_connect(state)}
  end

  @impl true
  def handle_call(:get_shadow, _from, state) do
    {:reply, state.shadow, state}
  end

  def handle_call({:command, cmd, args, timeout}, from, %{status: :ready} = state) do
    case state.adapter.encode_command(cmd, args, state.adapter_state) do
      {:ok, packet, req_id, new_adapter_state} ->
        send_packet(state.transport, state.socket, state.dest_host, state.dest_port, packet)

        timer_ref = Process.send_after(self(), {:rpc_timeout, req_id}, timeout)
        new_queue = Map.put(state.rpc_queue, req_id, {from, timer_ref})

        {:noreply, %{state | adapter_state: new_adapter_state, rpc_queue: new_queue}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:command, _cmd, _args, _timeout}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  @impl true
  def handle_cast({:set_shadow, changes}, state) do
    new_shadow = Shadow.apply_event(state.shadow, {:set, changes})
    PubSub.broadcast_shadow(new_shadow)
    {:noreply, %{state | shadow: new_shadow}}
  end

  # Network & Async Messages

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    :inet.setopts(socket, active: :once)
    {:noreply, process_incoming_data(data, state)}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("[Domex.Session] Device #{state.id} TCP closed")
    {:noreply, handle_disconnect(state, :tcp_closed)}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("[Domex.Session] Device #{state.id} TCP error: #{inspect(reason)}")
    {:noreply, handle_disconnect(state, reason)}
  end

  def handle_info({:udp, socket, _ip, _port, data}, %{socket: socket} = state) do
    :inet.setopts(socket, active: :once)
    {:noreply, process_incoming_data(data, state)}
  end

  def handle_info({:rpc_timeout, req_id}, state) do
    case Map.pop(state.rpc_queue, req_id) do
      {{from, _timer_ref}, remaining_queue} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | rpc_queue: remaining_queue}}

      {nil, _} ->
        {:noreply, state}
    end
  end

  def handle_info(:reconnect, state) do
    {:noreply, attempt_connect(state)}
  end

  def handle_info(:poll, %{status: :ready} = state) do
    state =
      case state.adapter.poll(state.adapter_state) do
        {:ok, packets, new_adapter_state} when is_list(packets) ->
          Enum.each(packets, fn p ->
            send_packet(state.transport, state.socket, state.dest_host, state.dest_port, p)
          end)

          %{state | adapter_state: new_adapter_state}

        _ ->
          state
      end

    poll_timer = Process.send_after(self(), :poll, @default_poll_interval_ms)
    {:noreply, %{state | poll_timer: poll_timer}}
  end

  def handle_info(:poll, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    close_socket(state.transport, state.socket)
    fail_pending_rpcs(state.rpc_queue, :session_terminating)
    :ok
  end

  # Internal Helpers

  defp attempt_connect(state) do
    # Cancel any pending reconnect timer
    if state.reconnect_timer, do: Process.cancel_timer(state.reconnect_timer)

    case state.adapter.connect_opts(state.adapter_state) do
      {:ok, host, port, opts} ->
        case open_connection(state.transport, host, port, opts) do
          {:ok, socket} ->
            {:ok, initial_packets, new_adapter_state} =
              state.adapter.handle_connected(state.adapter_state)

            Enum.each(initial_packets, fn packet ->
              send_packet(state.transport, socket, host, port, packet)
            end)

            new_shadow = Shadow.apply_event(state.shadow, {:online, true})
            PubSub.broadcast_shadow(new_shadow)

            poll_timer = Process.send_after(self(), :poll, @default_poll_interval_ms)

            %{
              state
              | socket: socket,
                dest_host: host,
                dest_port: port,
                status: :ready,
                shadow: new_shadow,
                adapter_state: new_adapter_state,
                backoff_ms: @initial_backoff_ms,
                reconnect_timer: nil,
                poll_timer: poll_timer
            }

          {:error, _reason} ->
            schedule_reconnect(state)
        end

      {:error, _reason} ->
        schedule_reconnect(state)
    end
  end

  defp open_connection(:tcp, host, port, opts) do
    :gen_tcp.connect(host, port, opts, 3_000)
  end

  defp open_connection(:udp, _host, _port, opts) do
    # For UDP, open an ephemeral local socket
    :gen_udp.open(0, opts)
  end

  defp send_packet(:tcp, socket, _host, _port, packet) do
    :gen_tcp.send(socket, packet)
  end

  defp send_packet(:udp, socket, host, port, packet) do
    :gen_udp.send(socket, host, port, packet)
  end

  defp close_socket(:tcp, socket) when not is_nil(socket), do: :gen_tcp.close(socket)
  defp close_socket(:udp, socket) when not is_nil(socket), do: :gen_udp.close(socket)
  defp close_socket(_transport, _socket), do: :ok

  defp process_incoming_data(raw_data, state) do
    case state.adapter.handle_data(raw_data, state.adapter_state) do
      {:ok, events, replies, new_adapter_state} ->
        # 1. Update shadow with events
        new_shadow =
          Enum.reduce(events, state.shadow, fn event, acc ->
            Shadow.apply_event(acc, event)
          end)

        if new_shadow != state.shadow do
          PubSub.broadcast_shadow(new_shadow)
        end

        # 2. Resolve pending RPCs
        new_queue =
          Enum.reduce(replies, state.rpc_queue, fn {req_id, reply_val}, acc ->
            case Map.pop(acc, req_id) do
              {{from, timer_ref}, rest} ->
                Process.cancel_timer(timer_ref)
                GenServer.reply(from, reply_val)
                rest

              {nil, rest} ->
                rest
            end
          end)

        %{state | shadow: new_shadow, adapter_state: new_adapter_state, rpc_queue: new_queue}

      {:error, _reason} ->
        state
    end
  end

  defp handle_disconnect(state, reason) do
    close_socket(state.transport, state.socket)
    fail_pending_rpcs(state.rpc_queue, {:connection_lost, reason})

    new_shadow = Shadow.apply_event(state.shadow, {:disconnected, reason})
    PubSub.broadcast_shadow(new_shadow)

    schedule_reconnect(%{state | socket: nil, status: :disconnected, shadow: new_shadow})
  end

  defp schedule_reconnect(state) do
    backoff = state.backoff_ms
    next_backoff = min(backoff * 2, @max_backoff_ms)
    timer_ref = Process.send_after(self(), :reconnect, backoff)

    %{state | status: :disconnected, backoff_ms: next_backoff, reconnect_timer: timer_ref}
  end

  defp fail_pending_rpcs(queue, reason) do
    Enum.each(queue, fn {_req_id, {from, timer_ref}} ->
      Process.cancel_timer(timer_ref)
      GenServer.reply(from, {:error, reason})
    end)
  end

  defp resolve_adapter(mod) when is_atom(mod), do: mod

  defp resolve_adapter(str) when is_binary(str) do
    case str do
      "Domex.Adapter.YeelightLan" -> Domex.Adapter.YeelightLan
      "Domex.Adapter.MiioDevice" -> Domex.Adapter.MiioDevice
      "Domex.Adapter.MideaDevice" -> Domex.Adapter.MideaDevice
      "yeelight" -> Domex.Adapter.YeelightLan
      "miio" -> Domex.Adapter.MiioDevice
      "midea" -> Domex.Adapter.MideaDevice
      other -> String.to_existing_atom(other)
    end
  end

  defp to_server(id) when is_binary(id) or is_atom(id), do: DevRegistry.via_tuple(id)
  defp to_server(pid) when is_pid(pid), do: pid
end
