# GL.iNet WAN Split

`wan-split` is a tiny OpenWrt/GL.iNet policy-routing controller for one extremely specific multi-WAN problem:

You have a bunch of LAN clients uploading to the same application, CDN, API, storage endpoint, or VPN-like destination, and the router's built-in load balancing keeps shoving most of that traffic onto one WAN.

This is not bonding. It will not make one upload, one speed test, one TCP connection, or one VPN tunnel magically use two cell modems at once. That requires a real aggregation layer somewhere else in the chain -- Speedify, Peplink SpeedFusion, MPTCP, a cooperating server, whatever flavor of tunnel math you trust that week.

This does the simpler, dumber, very useful thing: it assigns whole client devices to different healthy WANs. So if you have 20 phones, cameras, encoders, laptops, or upload boxes all hitting the same destination, `wan-split` can spread those devices across cellular, tethering, Ethernet, repeater, or other WAN links instead of letting one uplink do all the work while the other one sits there looking decorative.

## Why this exists

GL.iNet's Multi-WAN Load Balance mode is connection based, which means the router makes a decision when a connection starts and then mostly leaves that connection alone. The official GL.iNet docs say the load ratio is used when assigning interfaces for new connections, and that active traffic is not guaranteed to match the load ratio over short windows:

https://docs.gl-inet.com/router/en/4/interface_guide/multi-wan/

That behavior is normal. It is also the exact wrong shape for a certain kind of field workflow:

- dozens of upload devices all hit one CDN or ingest provider
- every client behaves similarly and sends roughly equal traffic
- you care more about aggregate site throughput than any single client's peak speed
- you need a simple iPad-friendly kill switch during a live deployment

`wan-split` solves that shape by assigning each DHCP client source IP to one healthy WAN with Linux policy routing -- basically, "this device leaves through this uplink" rules installed directly into the router.

## Tested Scenario

The original deployment was built and tested on a GL.iNet X2000-series cellular router running stock GL.iNet firmware:

- OpenWrt 19.07-SNAPSHOT based firmware
- Linux kernel 5.4.213
- `ipq50xx/generic`, `aarch64_cortex-a53_neon-vfpv4`
- 2 CPU cores
- about 385 MB RAM
- about 38 MB overlay, with about 35 MB free during testing
- stock GL.iNet Multi-WAN stack left in place
- Tailscale present on the router, but not required by this tool

WANs tested:

- built-in cellular modem, OpenWrt logical interface `modem_2_1`, device `wwan0_1`
- USB/mobile tethering, OpenWrt logical interface `tethering`, device `eth2`

Live checks confirmed source-based route selection for real LAN clients. Shadow tests exercised 12, 8, and 13 synthetic clients across two WANs without touching live client routes, because bricking your live internet edge during a test is a hobby for someone else.

## Features

- Runtime-only enable flag: rebooting the router disables the split and returns to normal GL.iNet routing.
- LAN dashboard at `/wan-split/index.html` with ENABLE, DISABLE, and REBALANCE buttons.
- Per-WAN TX/RX counters and browser-calculated outbound Mbps estimate.
- Client table showing installed clients plus newly planned clients that will be picked up on rebalance.
- Optional throughput-aware mode that samples per-client upload rates and assigns heavier clients to less-utilized, higher-capacity WANs.
- WAN health checks before assigning clients.
- Hotplug rebalancing when interfaces go up or down.
- Even-count assignment mode for roughly equal client counts per WAN.
- Hash mode for more stable assignment if client churn matters more than exact count balance.
- No dependency on `mwan3`, LuCI, Python, Node, or a cloud service.

## Security Model

The dashboard is intentionally not secured. Not "I forgot to add auth." Intentionally.

There is no login, token, CSRF protection, HTTPS requirement, or per-user authorization in `/www/wan-split/index.html` or `/www/cgi-bin/wan-split-control`. Any device that can reach the router's LAN web server can enable, disable, or rebalance WAN splitting.

That was a deliberate choice for isolated live-production networks where the operator may only have an iPad and needs an immediate kill switch. Do not expose this dashboard on an untrusted LAN, guest Wi-Fi, public Wi-Fi, or the WAN side of the router.

If you need security, put it behind your own firewall rules, HTTP auth, VPN-only management network, or a separate authenticated control plane before using it outside a tightly controlled LAN.

## How It Works

`wan-split` reads current DHCP leases from `/tmp/dhcp.leases`, filters clients in the LAN `/24`, checks which configured WAN interfaces are up and healthy, then installs a few boring but powerful Linux routing primitives:

- one routing table per active WAN
- one default route in each WAN table
- one LAN route in each WAN table
- one `ip rule` per assigned client source IP

The rules are source based, so a client keeps using its assigned WAN for outbound traffic until the next rebalance or disable event. Source based just means the router is looking at where the traffic came from on your LAN, not which CDN hostname it happens to be yelling at.

Example:

```text
client A -> WAN tethering
client B -> WAN modem_2_1
client C -> WAN tethering
client D -> WAN modem_2_1
```

If one WAN fails health checks, all clients are moved to the remaining healthy WANs. If no WAN is healthy, the tool removes its policy routes instead of leaving stale rules behind.

## Throughput Mode

The default mode is still `balanced`, which spreads clients by count. That is the safest mode and it is the one you should use first.

`throughput` mode is for the next problem: one client is doing 40 Mbps, another is doing 2 Mbps, and pretending those two clients are equal is silly.

When `ASSIGNMENT_MODE=throughput`, `wan-split` can sample per-client upload counters using a tiny `iptables` mangle chain, smooth those samples into recent bitrates, and then assign clients greedily:

1. Sort clients from heaviest to lightest.
2. Look at each healthy WAN's configured capacity.
3. Put the next client on the WAN with the lowest projected utilization.
4. If utilization is tied, prefer fewer clients.
5. If that is still tied, prefer the bigger WAN.

So a 120 Mbps WAN gets treated differently than a 40 Mbps WAN. Not perfectly, because cellular is cellular and sometimes the laws of radio propagation show up with a chair, but better than "six clients here, six clients there."

Example config:

```sh
ASSIGNMENT_MODE=throughput
INTERFACES="tethering modem_2_1 wan"
WAN_CAPACITY_MBPS="tethering:80 modem_2_1:60 wan:100"
ACCOUNTING=1
CLIENT_RATE_ALPHA=70
MIN_SAMPLE_SECONDS=2
```

The dashboard samples rates while enabled and shows per-client outbound Mbps. `wan-split rebalance` uses the latest samples to move clients. There is no always-on background loop yet. That is deliberate. In a live upload workflow, a manual REBALANCE button is much easier to trust than a hidden daemon moving clients every few seconds because it thinks it is being helpful.

## Install

Back up the router first. Seriously. This is a small tool, but it still edits the part of the box responsible for your internet existing. On GL.iNet firmware, use the web UI's backup/export option, or run a manual backup over SSH.

Copy this repository to the router, then run:

```sh
cd glinet-wan-split
sh install.sh
```

The installer copies files to:

```text
/usr/bin/wan-split
/etc/wan-split.conf
/etc/init.d/wan-split
/etc/hotplug.d/iface/95-wan-split
/www/wan-split/index.html
/www/cgi-bin/wan-split-control
```

It also creates a timestamped backup tarball under `/root` if any existing files are present.

The install does not enable WAN splitting. After installation:

```sh
wan-split dry-run
wan-split on
wan-split status
```

Open the dashboard:

```text
http://ROUTER_IP/wan-split/index.html
```

For the original GL.iNet LAN, this was:

```text
http://192.168.7.1/wan-split/index.html
```

## Configuration

Edit `/etc/wan-split.conf`.

Important settings:

```sh
ENABLED=0
INTERFACES="tethering modem_2_1 wan secondwan wwan"
PRIO=25300
TABLE_BASE=20010
ASSIGNMENT_MODE=balanced
WAN_CAPACITY_MBPS=""
WAN_CAPACITY_DEFAULT_MBPS=60
ACCOUNTING=1
HEALTH_CHECK=1
HEALTH_TARGETS="1.1.1.1 8.8.8.8"
EXCLUDE_IPS=""
```

Keep `ENABLED=0` unless you intentionally want boot-time behavior. The default is designed so rebooting the router is the emergency exit. Pull power, let it come back, normal GL.iNet routing returns.

Use `INTERFACES` to list OpenWrt logical interface names, not raw Linux device names. You can inspect them with:

```sh
ifstatus tethering
ifstatus modem_2_1
ifstatus wan
```

## Commands

```sh
wan-split dry-run     # show active WANs and planned assignments
wan-split on          # enable for this runtime and apply rules
wan-split off         # disable and remove rules
wan-split sample      # update per-client throughput counters
wan-split rebalance   # recompute assignments now
wan-split status      # show config, WANs, assignments, and installed rules
wan-split stop        # remove rules without changing runtime enable state
```

## Testing

Local mock tests:

```sh
tests/run-mock-tests.sh
```

These test:

- 12 clients split 6/6 over two WANs
- throughput mode across three WANs with 120/80/40 Mbps capacity hints
- heavy-client placement onto higher-capacity/lower-utilization WANs
- third-WAN drop and reassignment to remaining WANs
- one WAN down, all clients moved to the other WAN
- all WANs down, no assignments
- runtime enable marker behavior
- route cleanup on disable

Accounting tests:

```sh
tests/run-accounting-tests.sh
```

These mock `iptables-save` counter output and verify that byte deltas become per-client bitrates.

Router shadow test:

```sh
tests/router-shadow-test.sh
```

The shadow test is intended to run on the router. It uses separate test priorities and route table numbers so it can validate assignment behavior without touching live client routes.

It tests:

- 12 clients -> 6/6 split
- 8 clients -> 4/4 split
- 13 clients -> 7/6 split
- tethering-only failover
- cellular-only failover
- no-active-WAN cleanup

## Good Fits

- mobile production kits with many upload devices
- camera fleets uploading to one ingest/CDN
- field teams with many phones/tablets pushing media
- cheap cellular + tethering setups where Peplink/Speedify-style bonding is too heavy, too expensive, or just too much ceremony
- kiosks or appliances all hitting one API/storage provider
- temporary event networks where a simple reboot-safe kill switch matters more than elegance

## Bad Fits

- making one client faster than one WAN
- making one upload span multiple WANs
- improving a single speed test result
- replacing true tunnel bonding, MPTCP, SD-WAN, Speedify, Peplink SpeedFusion, or AstroWarp-style aggregation
- untrusted networks where an open LAN dashboard is unacceptable

## mwan3 Comparison

`mwan3` is the mature OpenWrt multi-WAN package and is the better long-term choice for many standard OpenWrt deployments. It has richer policy, tracking, sticky, and failover behavior.

This project exists because the original target was a stock GL.iNet router with the GL Multi-WAN stack already installed, an operator-controlled LAN, and a need for a very small source-IP splitter plus a no-login iPad dashboard. It does not try to replace `mwan3`.

On newer GL.iNet firmware, GL's Multi-WAN system is often handled by `kmwan`. GL forum staff repeatedly warn that `kmwan` and `mwan3` can conflict, so using `mwan3` usually means disabling GL's built-in Multi-WAN service first. That may be fine on a lab router. On a live router you need in a few days, that is exactly the kind of "while we're in here" project that can eat an afternoon.

Use `mwan3` when you want a standard OpenWrt package and are comfortable replacing or bypassing vendor Multi-WAN behavior. Use `wan-split` when you want a small, reversible, source-client distribution layer on top of an existing GL.iNet setup.

## Uninstall

```sh
sh uninstall.sh
```

Or manually:

```sh
wan-split off
rm -f /usr/bin/wan-split
rm -f /etc/wan-split.conf
rm -f /etc/init.d/wan-split
rm -f /etc/hotplug.d/iface/95-wan-split
rm -rf /www/wan-split
rm -f /www/cgi-bin/wan-split-control
```
