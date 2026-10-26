import Config

mqtt_host = System.get_env("DOMEX_MQTT_HOST")

default_mqtt_mode =
  cond do
    config_env() == :test -> "disabled"
    mqtt_host -> "external"
    true -> "embedded"
  end

mqtt_mode =
  case System.get_env("DOMEX_MQTT_MODE", default_mqtt_mode) do
    "embedded" -> :embedded
    "external" -> :external
    "disabled" -> :disabled
    _ -> raise "DOMEX_MQTT_MODE must be embedded, external or disabled"
  end

mqtt_ip =
  case :inet.parse_address(String.to_charlist(System.get_env("DOMEX_MQTT_BIND", "0.0.0.0"))) do
    {:ok, ip} -> ip
    {:error, _} -> raise "DOMEX_MQTT_BIND must be an IP address"
  end

config :domex_core, :sensor_mqtt,
  mode: mqtt_mode,
  host: mqtt_host || "localhost",
  ip: mqtt_ip,
  port: String.to_integer(System.get_env("DOMEX_MQTT_PORT", "1883")),
  tls: System.get_env("DOMEX_MQTT_TLS", "false") in ["true", "1"],
  cacertfile: System.get_env("DOMEX_MQTT_CA_CERT"),
  certfile: System.get_env("DOMEX_MQTT_CERT_FILE"),
  keyfile: System.get_env("DOMEX_MQTT_KEY_FILE"),
  user_name: System.get_env("DOMEX_MQTT_USERNAME"),
  password: System.get_env("DOMEX_MQTT_PASSWORD"),
  client_id: System.get_env("DOMEX_MQTT_CLIENT_ID", "domex-hub"),
  prefix: System.get_env("DOMEX_MQTT_PREFIX", "domex/sensors")

if System.get_env("PHX_SERVER") do
  config :domex_web, DomexWeb.Endpoint, server: true
end

config :domex_web, DomexWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4066"))]

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :domex_web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :domex_web, DomexWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base
end
