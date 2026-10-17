import Config

config :domex_web,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :domex_web, DomexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DomexWeb.ErrorHTML, json: DomexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Domex.PubSub,
  live_view: [signing_salt: "McgtPV5f"]

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  domex_web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/domex_web/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind
config :tailwind,
  version: "4.1.12",
  domex_web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/domex_web", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
