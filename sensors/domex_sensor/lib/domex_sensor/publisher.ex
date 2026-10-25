defmodule DomexSensor.Publisher do
  @moduledoc "Keeps only the latest snapshot while offline and republishes it after reconnect."
  use GenServer
  require Logger

  alias Domex.Protocol.Sensor

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(is_nil(name), do: [], else: [name: name]))
  end

  def report(snapshot, server \\ __MODULE__), do: GenServer.cast(server, {:snapshot, snapshot})
  def connection(status, server \\ __MODULE__), do: GenServer.cast(server, {:connection, status})
  def offline(server \\ __MODULE__), do: GenServer.call(server, :offline)

  def connection_options(options) do
    prefix = Keyword.fetch!(options, :prefix)
    id = Keyword.fetch!(options, :identity).sensor_id

    ([
       client_id: Keyword.fetch!(options, :client_id),
       server: server(options),
       handler: {DomexSensor.MQTTHandler, [publisher: Keyword.get(options, :name, __MODULE__)]},
       keep_alive: 15,
       will: %Tortoise311.Package.Publish{
         topic: Sensor.topic(prefix, id, :availability),
         payload: "offline",
         qos: 1,
         retain: true
       }
     ] ++ Keyword.take(options, [:user_name, :password]))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp server(options) do
    transport_options = [
      host: Keyword.fetch!(options, :host),
      port: Keyword.fetch!(options, :port)
    ]

    if Keyword.get(options, :tls, false) do
      trust =
        case Keyword.get(options, :cacertfile) do
          nil -> [cacerts: :public_key.cacerts_get()]
          file -> [cacertfile: String.to_charlist(file)]
        end

      {Tortoise311.Transport.SSL, transport_options ++ [verify: :verify_peer] ++ trust}
    else
      {Tortoise311.Transport.Tcp, transport_options}
    end
  end

  @impl true
  def init(options) do
    interval = Keyword.get(options, :publish_interval_ms, 1_000)
    timer = Process.send_after(self(), :publish, interval)

    {:ok,
     %{
       options: options,
       latest: nil,
       connected?: false,
       stopping?: false,
       interval: interval,
       timer: timer,
       publish: Keyword.get(options, :publish, &Tortoise311.publish_sync/4)
     }}
  end

  @impl true
  def handle_cast({:snapshot, snapshot}, state), do: {:noreply, %{state | latest: snapshot}}

  def handle_cast({:connection, :up}, %{stopping?: false} = state) do
    state = %{state | connected?: true}
    publish(state, :availability, "online", 1)
    publish_latest(state)
    {:noreply, state}
  end

  def handle_cast({:connection, _status}, state), do: {:noreply, %{state | connected?: false}}

  @impl true
  def handle_call(:offline, _from, state) do
    if state.connected?, do: publish(state, :availability, "offline", 1)
    {:reply, :ok, %{state | connected?: false, stopping?: true}}
  end

  @impl true
  def handle_info(:publish, state) do
    if state.connected?, do: publish_latest(state)
    timer = Process.send_after(self(), :publish, state.interval)
    {:noreply, %{state | timer: timer}}
  end

  defp publish_latest(%{latest: nil}), do: :ok

  defp publish_latest(state) do
    identity = Keyword.fetch!(state.options, :identity)
    publish(state, :state, Sensor.encode_state(identity, state.latest), 0)
  end

  defp publish(state, kind, payload, qos) do
    options = state.options

    topic =
      Sensor.topic(
        Keyword.fetch!(options, :prefix),
        Keyword.fetch!(options, :identity).sensor_id,
        kind
      )

    case state.publish.(Keyword.fetch!(options, :client_id), topic, payload,
           qos: qos,
           retain: true,
           timeout: 500
         ) do
      :ok -> :ok
      {:error, reason} -> publish_error(kind, reason)
    end
  catch
    :exit, _ -> publish_error(kind, :disconnected)
  end

  defp publish_error(kind, reason) do
    Logger.warning("Sensor MQTT #{kind} publish failed: #{inspect(reason)}")
    {:error, reason}
  end
end
