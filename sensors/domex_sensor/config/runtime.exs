import Config

config :domex_sensor, :options, DomexSensor.Config.from_env(System.get_env())
