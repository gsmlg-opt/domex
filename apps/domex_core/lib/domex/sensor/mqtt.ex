defmodule Domex.Sensor.MQTT do
  @moduledoc "MQTT subscriber for standalone sensor state; enabled when a broker is configured."
  use Tortoise311.Handler

  alias Domex.Protocol.Sensor
  alias Domex.Sensor.Store

  def child_spec(options) do
    prefix = Keyword.get(options, :prefix, Sensor.default_prefix())
    host = Keyword.fetch!(options, :host)
    port = Keyword.get(options, :port, 1883)

    server =
      if Keyword.get(options, :tls, false) do
        trust =
          case Keyword.get(options, :cacertfile) do
            nil -> [cacerts: :public_key.cacerts_get()]
            file -> [cacertfile: String.to_charlist(file)]
          end

        {Tortoise311.Transport.SSL, [host: host, port: port, verify: :verify_peer] ++ trust}
      else
        {Tortoise311.Transport.Tcp, host: host, port: port}
      end

    connection_options =
      [
        client_id: Keyword.get(options, :client_id, "domex-hub"),
        server: server,
        handler: {__MODULE__, [prefix: prefix, store: Keyword.get(options, :store, Store)]},
        subscriptions: Sensor.subscriptions(prefix),
        keep_alive: 15
      ] ++
        (Keyword.take(options, [:user_name, :password])
         |> Enum.reject(fn {_key, value} -> is_nil(value) end))

    Tortoise311.Connection.child_spec(connection_options)
  end

  @impl true
  def init(options), do: {:ok, Map.new(options)}

  @impl true
  def connection(:down, state) do
    Store.disconnected(state.store)
    {:ok, state}
  end

  def connection(_status, state), do: {:ok, state}

  @impl true
  def handle_message(levels, payload, state) do
    case Sensor.decode(Enum.join(levels, "/"), payload, state.prefix) do
      {:ok, id, event} -> Store.ingest(id, event, state.store)
      {:error, _} -> :ok
    end

    {:ok, state}
  end
end
