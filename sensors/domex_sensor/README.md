# Domex Sensor

A standalone OTP application for macOS and Linux system monitoring. It lives
outside the hub's umbrella so it can be built and deployed independently. The
only shared application is `domex_protocol`, a local path dependency containing
the MQTT message contract; Phoenix and `domex_core` are not part of the release.

## Collectors

- **macOS Apple Silicon and Intel:** the native probes and metric calculations
  adapted from `hologram_demo`'s system monitor. Reports aggregate/per-core CPU
  usage, performance/efficiency core types when reported by the OS, memory,
  pressure, swap, disk throughput/IOPS, network traffic, process/thread counts,
  and GPU utilization when IOKit exposes it.
- **Linux:** reads `/proc` and `/sys` without root. Reports aggregate/per-core
  CPU, memory/swap, whole-disk I/O, network traffic and process/thread counts.
  macOS-only readings and GPU utilization remain unavailable.

Both collectors sample once per second and keep at most 60 samples locally.
CPU percentages and rates need two samples; unknown readings are JSON `null`.
Rates use elapsed monotonic time and rebaseline on counter resets, probe
restarts or changes in CPU, disk or interface topology.

## Run during development

From this directory, with Elixir 1.18+ and Erlang/OTP 27+ installed:

```sh
mix deps.get
DOMEX_MQTT_HOST=broker.local DOMEX_SENSOR_ID=desk-mac mix run --no-halt
```

Use a stable, unique sensor ID for each device. The default is derived from the
hostname. Sensors and the hub connect as clients to an external MQTT 3.1.1 broker
(for example Mosquitto or EMQX).

Start the hub from the repository root with the same broker and topic prefix:

```sh
DOMEX_MQTT_HOST=broker.local mix phx.server
```

Open `/sensors` in the hub. Sensors appear automatically; no manual device entry
is required. The hub keeps 60 distinct received samples per sensor, marks
disconnected sensors offline, and expires availability after 60 seconds without
telemetry. MQTT ingestion stays disabled on the hub unless `DOMEX_MQTT_HOST` is set.

## Runtime configuration

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `DOMEX_SENSOR_ID` | `sensor-<hostname>` | Stable topic identifier; 1-128 letters, digits, dots, underscores or hyphens, starting with a letter or digit |
| `DOMEX_SENSOR_NAME` | Hostname | Display name |
| `DOMEX_MQTT_HOST` | `localhost` | Broker hostname |
| `DOMEX_MQTT_PORT` | `1883` | Broker port; set `8883` explicitly for the usual TLS port |
| `DOMEX_MQTT_USERNAME` | Unset | Optional broker username |
| `DOMEX_MQTT_PASSWORD` | Unset | Optional broker password |
| `DOMEX_MQTT_TLS` | `false` | `true` enables TLS with peer verification |
| `DOMEX_MQTT_CA_CERT` | OS trust store | Optional PEM CA certificate path |
| `DOMEX_MQTT_PREFIX` | `domex/sensors` | Topic namespace shared with the hub |
| `DOMEX_SENSOR_PUBLISH_INTERVAL_MS` | `1000` | Publish interval, 250-30000 ms; collection remains once per second |

Broker variables are also supported by the hub. Set `DOMEX_MQTT_CLIENT_ID` on
the hub if multiple hub instances connect to one broker. Sensor client IDs are
derived from `DOMEX_SENSOR_ID`.

## Standalone release

Build on a machine matching the target OS, architecture and compatible system
libraries. Produce separate artifacts for macOS arm64, macOS x86_64 and each
Linux architecture/libc combination you deploy. This does not cross-compile
Erlang or the macOS probe.

```sh
mix deps.get --only prod
MIX_ENV=prod mix release domex_sensor
```

On macOS, the build machine needs Xcode Command Line Tools (`cc`). The release
step builds the correct Mach-O probe and includes it under the application's
`priv/native/bin` directory. Deployed devices need neither a C compiler nor
Elixir. Linux uses procfs and needs no native probe compilation.

Copy `_build/prod/rel/domex_sensor` to the device, then run:

```sh
DOMEX_MQTT_HOST=broker.local DOMEX_SENSOR_ID=desk-mac ./bin/domex_sensor start
```

The release bundles ERTS, needs compatible OS libraries such as OpenSSL, and has
its own runtime configuration. It does not require `SECRET_KEY_BASE`, web assets,
the source checkout, or a running hub to collect readings. Erlang distribution
is disabled by default. On broker loss, only the newest snapshot is retained for
reconnection rather than queuing a telemetry backlog.

For Linux, adapt `deploy/domex-sensor.service`, install the release at
`/opt/domex_sensor`, create the `domex-sensor` service user, and put runtime
variables in `/etc/domex-sensor.env`. The service user must be able to write the
release's runtime directory. Install the unit and enable it with systemd.

For macOS, adapt the absolute paths and environment in
`deploy/dev.domex.sensor.plist`, place it in `~/Library/LaunchAgents`, and load it
with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.domex.sensor.plist`.
Run it as the logged-in user; sampling does not require administrator privileges.

## MQTT contract (version 1)

- `<prefix>/<sensor_id>/state`: retained QoS 0 JSON with `schema_version: 1`,
  `sensor_id`, `name`, `hostname`, `platform`, `status` (`warming`, `live`, `error`),
  `error`, and `sample`. Local history is not transmitted.
- `<prefix>/<sensor_id>/availability`: retained QoS 1 `online` or `offline`.
  The connection registers `offline` as its last will and also publishes it on
  graceful shutdown. Availability is tracked separately from collector errors.

The hub validates the topic identifier, payload identity/version and sample
shape, rejects messages larger than 1 MiB, and bounds the store at 1000 sensors.
Use broker authentication and topic ACLs to control which devices may publish.

## Verification

```sh
mix precommit
```

Tests cover macOS metric semantics and platform selection, Linux procfs parsing,
port framing/restarts, bounded histories, configuration validation, publishing
while disconnected, graceful availability, and a real TCP MQTT reconnect.
The umbrella's tests and `mix precommit` run separately from this project's tests.
