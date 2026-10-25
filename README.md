# Domex

Domex is a local smart home management and control platform built with Elixir/OTP and Phoenix LiveView. Its LAN device protocols use pure binary pattern matching and Sans-I/O codecs with zero external protocol dependencies, alongside dynamic per-device supervision, real-time shadow synchronization over `Phoenix.PubSub`, and an interactive LiveView dashboard. Standalone system sensors report through MQTT using Tortoise311.

---

## Architecture (Umbrella Structure)

Domex is organized as an Elixir umbrella project consisting of three decoupled applications, with a separately released sensor project under `sensors/domex_sensor`:

```text
domex/
├── apps/
│   ├── domex_protocol/       # Pure Sans-I/O binary codecs (zero side-effects)
│   │   ├── Yeelight LAN (CRLF framing, JSON-RPC, SSDP advertisement parsing)
│   │   ├── Xiaomi miIO / MIoT (32-byte header, MD5 keys, AES-128-CBC PKCS#7, SIID/PIID)
│   │   └── Midea AC (0x5A5A / 0x8370 frames, 0xAA appliance payloads, CRC-8 / checksum)
│   │
│   ├── domex_core/           # OTP core, session management & network discovery
│   │   ├── Domex facade API (`Domex.list_devices/0`, `Domex.set_power/2`, etc.)
│   │   ├── Domex.Device.Session (Per-device GenServer state machine & RPC queue)
│   │   ├── Domex.Device.Shadow (Pure immutable shadow state reducer)
│   │   ├── Domex.Device.DynamicSupervisor & Registry
│   │   ├── Domex.Discovery (SSDP 1982, miIO UDP 54321, Midea UDP 6445)
│   │   ├── Domex.ConfigStore (DETS device persistence)
│   │   └── Domex.PubSub (Topic broadcast for shadow events)
│   │
│   └── domex_web/            # Phoenix 1.8 & LiveView 1.2 Web interface
│       ├── Gaoxy HTTP server & WebSocket endpoint
│       ├── UI system: phoenix_duskmoon & @duskmoon-dev/* custom elements
│       ├── Bundler: duskmoon_bundler (native Rust NIFs; no Node.js/esbuild/tailwind CLI required)
│       ├── DashboardLive (Real-time device grid & manual device modal)
│       ├── DeviceLive (Detailed diagnostics & interactive controls)
│       └── Live components (LightControl, AcControl, GenericSwitch)
└── sensors/
    └── domex_sensor/         # Independent Mix project and OTP release for macOS/Linux
        ├── macOS native CPU, memory, disk, network and GPU collectors
        ├── Linux procfs collector
        └── MQTT telemetry and retained availability
```

---

## Getting Started

### Prerequisites

- Elixir 1.18+
- Erlang/OTP 27+

### Setup and Running

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Build assets:
   ```bash
   mix assets.build
   ```

3. Run the Phoenix server:
   ```bash
   mix phx.server
   ```
   Or inside IEx:
   ```bash
   iex -S mix phx.server
   ```

4. Open [http://localhost:4000](http://localhost:4000) in your browser.

---

## System Sensors

The standalone [sensor project](sensors/domex_sensor/README.md) runs on macOS
(Apple Silicon and Intel) and Linux. It shares only the pure protocol app with
the hub and does not include Phoenix in its release.

Point the hub and sensors at the same MQTT broker, then open `/sensors`:

```sh
# From the repository root
DOMEX_MQTT_HOST=broker.local mix phx.server

# From sensors/domex_sensor
mix deps.get
DOMEX_MQTT_HOST=broker.local DOMEX_SENSOR_ID=desk-mac mix run --no-halt
```

Build an independent device release from `sensors/domex_sensor` with
`MIX_ENV=prod mix release domex_sensor`. See the sensor README for configuration
and macOS launchd / Linux systemd deployment templates.

## Code Quality & Testing

Run all test suites across the umbrella:
```bash
mix test
```

Run precommit verification (formatting, unused deps check, compilation with warnings-as-errors, and tests):
```bash
mix precommit
```

The standalone sensor has its own checks; run `mix precommit` from
`sensors/domex_sensor` as well.

<!-- TODO(upstream): duskmoon-dev/duskmoon-bundler#9 -->
Web asset generation on GNU Linux with glibc older than 2.43 is currently blocked
by the published DuskMoon Vize 10.0.5 native artifact
([upstream issue](https://github.com/duskmoon-dev/duskmoon-bundler/issues/9)).
The sensor release and both projects' `mix precommit` checks run independently
of that asset build. Resume asset verification after a compatible upstream
artifact is published and the dependency is updated.

