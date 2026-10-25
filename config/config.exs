import Config

config :domex_web,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :domex_web, DomexWeb.Endpoint,
  url: [host: "domex.local"],
  adapter: Gaoxy.PhoenixAdapter,
  # Hologram's SSE responses stay open beyond the ordinary request deadline.
  http: [http_limits: %{stream_timeout: :infinity}],
  render_errors: [
    formats: [html: DomexWeb.ErrorHTML, json: DomexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Domex.PubSub,
  live_view: [signing_salt: "McgtPV5f"]

# Configure duskmoon_bundler
config :duskmoon_bundler, :domex_web,
  entry: "apps/domex_web/assets/js/app.js",
  root: "apps/domex_web/assets",
  outdir: "apps/domex_web/priv/static/assets",
  resolve_dirs: ["apps", "deps", "node_modules", "apps/domex_web/node_modules"],
  external: ~w(/fonts/* /images/*),
  sourcemap: :hidden,
  tailwind: [
    css: "apps/domex_web/assets/css/app.css",
    sources: [
      %{base: "apps/domex_web/lib", pattern: "**/*.{ex,heex}"},
      %{base: "apps/domex_web/assets", pattern: "**/*.{css,js,ts,jsx,tsx}"},
      %{base: "deps/phoenix_duskmoon/lib", pattern: "**/*.{ex,heex}"},
      %{base: "deps/phoenix_duskmoon/assets/js", pattern: "**/*.{js,ts,jsx,tsx}"}
    ]
  ],
  server: [
    prefix: "/assets",
    watch_dirs: ["apps/domex_web/lib", "apps/domex_web/assets"]
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
