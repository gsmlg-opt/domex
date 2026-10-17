# Domex

Domex is a local smart home management and control platform built with Elixir/OTP and Phoenix LiveView. It operates with zero external protocol dependencies, leveraging pure binary pattern matching, Sans-I/O codecs, dynamic per-device supervision, real-time shadow synchronization over `Phoenix.PubSub`, and an interactive LiveView dashboard.

---

## Architecture (Umbrella Structure)

Domex is organized as an Elixir umbrella project consisting of three decoupled applications:

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
│   └── domex_web/            # Phoenix 1.8 & LiveView 1.1 Web interface
│       ├── Bandit HTTP server & WebSocket endpoint
│       ├── DashboardLive (Real-time device grid & manual device modal)
│       ├── DeviceLive (Detailed diagnostics & interactive controls)
│       └── Live components (LightControl, AcControl, GenericSwitch)
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

## Code Quality & Testing

Run all test suites across the umbrella:
```bash
mix test
```

Run precommit verification (formatting, unused deps check, compilation with warnings-as-errors, and tests):
```bash
mix precommit
```

