# Bypass AP Isolation for Reliable Wireless Debugging with a Dedicated Dongle

*Zero-config wireless scrcpy and ADB mirroring using a dedicated Wi-Fi dongle hotspot to bypass campus AP isolation and dynamic port hunting.*

## Problem

Developing on Android wirelessly over enterprise or university Wi-Fi networks is almost impossible due to **Access Point (AP) / Client Isolation**, which prevents devices on the same subnet from talking to each other. Furthermore, Android 11+ Wireless Debugging randomizes the TCP daemon port on every toggle and reconnect (in the ephemeral range `30000–49999`), requiring manual IP lookups and port discovery before every `adb connect` and `scrcpy` session. Reconnecting after walking away or waking the phone becomes tedious and disruptive to flow.

## Solution

Isolate the development traffic onto a private, dedicated USB Wi-Fi adapter (`dongle0`) hosting an isolated 5GHz/2.4GHz hotspot (`DevNet`) with a predictable subnet (`10.42.0.0/24`). 

The companion CLI script (`dev.sh`) automates the entire discovery and handoff lifecycle:
1. Verifies the dedicated interface and auto-activates the NetworkManager hotspot profile (`DevNet`).
2. Wakes the ARP table and discovers the phone's IP address on `10.42.0.0/24`.
3. Performs a fast TCP scan across `30000-49999` using `nmap` with an interactive spinner to resolve the active Android 11+ wireless debugging port.
4. Connects ADB and spawns `scrcpy` with low-latency streaming defaults (`1024p`, `60fps`, `6 Mbps`, screen turned off on the device).
5. Cleans up stale ADB sessions and restores terminal state on exit.

## Code

> Full script: [`scripts/scrcpy-wireless-dongle/dev.sh`](../scripts/scrcpy-wireless-dongle/dev.sh)

### Usage

#### Quick Start
Simply run the script with no arguments to discover the phone, scan ports, and launch scrcpy:
```bash
dev.sh
# or if placed in PATH as 'dev':
dev
```

#### CLI Options & Presets
```bash
# Specify target IP or port directly to skip discovery
dev.sh -p <PHONE_IP> --port 38455

# Use a quality preset (low | med | high | max)
dev.sh -q max

# Enable audio forwarding (disabled by default for minimal latency)
dev.sh --audio

# Keep the physical phone screen turned on during session
dev.sh --keep-screen-on

# Pass custom native scrcpy flags after '--'
dev.sh -- --record=demo.mp4 --always-on-top
```

#### Quality Presets
| Preset | Resolution | Bitrate | Framerate | Best For |
| :--- | :--- | :--- | :--- | :--- |
| `low` | 720p | 2 Mbps | 30 fps | Weak wireless signal / maximum battery efficiency |
| `med` | 1024p | 4 Mbps | 60 fps | Balanced performance |
| `high` *(default)* | 1024p | 6 Mbps | 60 fps | Ultra-low latency responsive touch & interaction |
| `max` | Native | 12 Mbps | 60 fps | High-fidelity UI review and recording |

## Bonus Feature: Automatic VPN Routing (TUN + NAT)

A powerful side-effect of this architecture is zero-touch, transparent VPN routing for the connected Android device:

- **The NAT Gateway (`ipv4.method shared`)**: NetworkManager's shared mode automatically spins up `dnsmasq` and establishes `iptables`/`nftables` MASQUERADE rules on the host. The laptop acts as the default gateway (`10.42.0.1`) for the phone, forwarding all Layer 3 packets into the host's networking stack.
- **The TUN Interface**: When running a proxy client like Clash Verge in **TUN Mode**, a virtual network device intercepts all outbound Layer 3 IP traffic passing through the host OS.
- **The Intersection**: Because the phone's inbound packets are NATted and handled by the host routing table, Clash Verge transparently captures and routes the phone's traffic through the encrypted proxy tunnel before egressing over the physical uplink.
- **The Benefits**:
  - **Campus DPI & Firewall Bypass**: The phone's traffic bypasses university Deep Packet Inspection (DPI) and firewall restrictions automatically.
  - **Zero Phone Setup**: Requires no VPN client, proxy profiles, or custom certificates installed on the Android device.
  - **Battery & Thermal Savings**: Offloads all cryptographic tunnel overhead to the laptop CPU, preventing device thermal throttling and battery drain during extended sessions.

## Notes

- **Network Interface Binding**: The script is pinned to the interface name `dongle0` and profile `DevNet`. If the dongle kernel module is unloaded after a system kernel upgrade, the script surfaces actionable error messages pointing to your local `fix-dongle.sh` recovery script / `fix-dongle.timer`.
- **Dynamic Port Scanning**: Android 11+ uses dynamic ephemeral ports for security. Scanning the full `30000-49999` range with `nmap -p 30000-49999 -T4 --open` typically takes under 1.5 seconds over a local hotspot.
- **Screen & Battery Savings**: Default flags pass `-S` (`--turn-screen-off`) and `-Sw` (`--stay-awake`), preventing the phone from heating up or discharging rapidly during continuous development.
- **Dependencies**: Requires `adb`, `scrcpy`, `nmap`, `nmcli`, and `ip` installed and available in `$PATH`.
