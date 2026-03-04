# reachable

A macOS command-line tool that monitors host reachability in a live terminal UI and exits automatically once all hosts are online.

## Features

- Concurrent checks — all hosts are probed simultaneously
- ICMP ping first, TCP port fallback (22, 445, 5900) if ping fails
- Live TUI with per-host status, method, and latency
- Once a host is confirmed reachable it is not re-checked
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
| `<host>` | One or more hostnames or IP addresses to monitor |

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
reachable donna.local joe.local gordon.local -i 5
```

## How It Works

For each host, `reachable` tries:

1. **ICMP ping** (`/sbin/ping -c 1 -W 1000`) — reports round-trip time in ms
2. **TCP connect** (`/usr/bin/nc -z`) on ports 22, 445, then 5900 — reports the port that responded

If both fail the host is marked **DOWN** and retried after the poll interval. Hosts confirmed reachable are not re-checked on subsequent rounds. The tool exits with status `0` once every host is reachable.
