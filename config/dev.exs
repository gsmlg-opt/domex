import Config

# For development, we disable any cache and enable
# debugging and code reloading.
config :domex_web, DomexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "9W0k1LMOi+1Args0AS2CQELCBE/MuY8aN264+n+gO7qVU5yJxBwJn6t+8B4D8lA7",
  watchers: [
    duskmoon_bundler: {Mix.Tasks.DuskmoonBundler.Dev, :run, [["domex_web", "--tailwind"]]}
  ]

# Reload browser tabs when matching files change.
config :domex_web, DomexWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/domex_web/router\.ex$"E,
      ~r"lib/domex_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :domex_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
