import Config

config :domex_sensor, enabled: config_env() != :test
