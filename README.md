# Reachable

A macOS command-line tool that monitors host reachability in a live terminal UI and exits automatically once all hosts are reachable.

## Features

- Concurrent checks — all hosts are probed simultaneously
- ICMP ping first, TCP port fallback (22, 445, 5900) if ping fails
- Live TUI with per-host status, method, and latency
- Wake-on-LAN — send a magic packet to sleeping Macs using `host@MAC` syntax
- Once a host is confirmed reachable it is not re-checked
- Exits with status `0` once all hosts are reachable — safe to use with `&&`
- Exits cleanly on ESC or Ctrl-C

## Requirements

- macOS 26 or later
- Swift 6.2 or later

## Build

```
swift build -c release
```

The binary is written to `.build/release/reachable`. Copy it somewhere on your `$PATH`:

```
cp .build/release/reachable /usr/local/bin/reachable
```

## Usage

```
reachable <host> [<host> ...] [--interval <seconds>]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<host>` | Hostname or IP address. Append `@MAC` to enable Wake-on-LAN (e.g. `host@aa:bb:cc:dd:ee:ff`) |

### Options

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--interval` | `-i` | `1.0` | Poll interval in seconds between retry rounds |
| `--help` | `-h` | | Show help |
| `--version` | `-v` | | Show version |

## Examples

Monitor a single host:
```
reachable 192.168.1.10
```

Monitor multiple hosts with a 5-second retry interval:
```
reachable 192.168.1.10 192.168.1.11 192.168.1.12 -i 5
```

Wake a sleeping Mac then SSH into it once it responds:
```
reachable mac.example.com@aa:bb:cc:dd:ee:ff && ssh mac.example.com
```

Mix hosts with and without Wake-on-LAN:
```
reachable 192.168.1.10 mac.example.com@aa:bb:cc:dd:ee:ff
```

## How It Works

For each host, `reachable` tries:

1. **ICMP ping** (`/sbin/ping -c 1 -W 1000`) — reports round-trip time in ms
2. **TCP connect** (`/usr/bin/nc -z`) on ports 22, 445, then 5900 — reports the port that responded

If both fail the host is marked **DOWN** and retried after the poll interval. Hosts confirmed reachable are not re-checked on subsequent rounds. The tool exits with status `0` once every host is reachable.

### Wake-on-LAN

Append `@MAC` to any host argument to enable Wake-on-LAN for that host. When the host is first detected as unreachable, a 102-byte magic packet (6× `0xFF` followed by 16 repetitions of the MAC address) is sent via UDP broadcast on port 9. The magic packet is sent once per run; the tool then continues polling until the Mac wakes and responds.

WOL requires the target Mac to have Wake-on-Magic-Packet enabled (`sudo pmset -a womp 1`) and be reachable on the local network or via a Tailscale.

#### MAC Address Privacy

MAC addresses are globally unique hardware identifiers. When you provide a MAC to this tool, keep in mind:

- **Local network (home, office)**: MAC addresses are broadcast-visible to all devices on the network anyway, so there is no additional privacy risk.
- **Tailscale**: The MAC address stays on your local network segment and is never transmitted through Tailscale or DERP relays. The tool sends the magic packet directly via local broadcast—it doesn't relay through Tailscale infrastructure.
- **Logging**: This tool does not log, store, or transmit MAC addresses anywhere. They only exist in your command-line invocation.

If you're concerned about MAC address exposure in larger or shared environments, use IP-based host checking instead and skip the `@MAC` syntax.
