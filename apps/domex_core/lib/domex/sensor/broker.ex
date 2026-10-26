defmodule Domex.Sensor.Broker do
  @moduledoc "Embedded MqttX listener for standalone sensors."

  alias Domex.Protocol.Sensor

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, type: :supervisor}
  end

  def start_link(options) do
    prefix = Keyword.get(options, :prefix, Sensor.default_prefix())

    unless Sensor.valid_prefix?(prefix), do: raise(ArgumentError, "invalid MQTT topic prefix")

    if is_nil(options[:user_name]) != is_nil(options[:password]) do
      raise ArgumentError, "set both DOMEX_MQTT_USERNAME and DOMEX_MQTT_PASSWORD"
    end

    handler_options = [
      prefix: prefix,
      store: Keyword.get(options, :store, Domex.Sensor.Store),
      user_name: options[:user_name],
      password: options[:password],
      transport_opts: %{max_packet_size: 1_048_576, max_retained_messages: 2_000}
    ]

    transport_options = [
      transport: MqttX.Transport.ThousandIsland,
      ip: Keyword.get(options, :ip, {0, 0, 0, 0}),
      port: Keyword.get(options, :port, 1883),
      num_acceptors: 10
    ]

    tls_options =
      if Keyword.get(options, :tls, false) do
        certfile = options[:certfile] || raise ArgumentError, "set DOMEX_MQTT_CERT_FILE for TLS"
        keyfile = options[:keyfile] || raise ArgumentError, "set DOMEX_MQTT_KEY_FILE for TLS"

        [
          transport_module: ThousandIsland.Transports.SSL,
          transport_options: [certfile: certfile, keyfile: keyfile]
        ]
      else
        []
      end

    MqttX.Server.start_link(
      Domex.Sensor.BrokerHandler,
      handler_options,
      transport_options ++ tls_options
    )
  end
end
