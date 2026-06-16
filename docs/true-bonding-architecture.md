# True Bonding Architecture Notes

This is the bigger version of the problem.

`wan-split` spreads whole client devices across WANs. True bonding splits traffic from one flow, sends pieces across multiple WANs, reassembles them on a server you control, and then exits to the public internet from there.

That is the thing people usually mean when they say "combine my two SIMs into one bigger pipe."

## The Simple Mental Model

```text
LAN device
  -> GL.iNet router
    -> bonding client
      -> WAN A tunnel \
      -> WAN B tunnel  -> home/VPS/fiber exit server -> internet/CDN
      -> WAN C tunnel /
```

The router-side client has to:

- create one tunnel path per WAN
- force each tunnel path out a specific WAN
- split packets or flows across those paths
- sequence traffic so the server can put it back together
- detect path loss and latency changes
- avoid melting latency with a giant reorder buffer

The server-side exit has to:

- accept all tunnel paths from the same router
- reassemble traffic
- NAT/forward to the public internet
- send return traffic back through the bonded tunnel
- handle failover when one WAN path dies

That is why a normal VPN server is not enough. A normal WireGuard/OpenVPN/Tailscale exit node moves encrypted traffic through one tunnel. A bonding exit node is also a packet scheduler and reassembly engine.

## Best Existing Starting Point

### OpenMPTCProuter

OpenMPTCProuter is the closest thing to the full idea already existing in open source.

- Website: https://www.openmptcprouter.com/
- Router repo: https://github.com/Ysurac/openmptcprouter
- VPS scripts: https://github.com/Ysurac/openmptcprouter-vps

It uses OpenWrt plus Multipath TCP, and its docs describe real aggregation across up to 8 connections. The GitHub README says it terminates over a VPS and can use MPTCP, MLVPN, and Glorytun UDP.

This is the real answer if the question is "what should we fork or study first?"

The catch: it is much closer to a firmware/distribution than a tiny plugin. MPTCP support is a kernel-level thing. The stock GL.iNet firmware on the X2000 is not something we should casually mutate into an MPTCP router the day before a live deployment.

Also, OpenMPTCProuter has build configs for several GL.iNet devices, including models like GL-MT3000, GL-MT6000, and GL-X3000, but that does not automatically mean the X2000 is a clean drop-in target. This wants a spare router or lab image first.

## Other Candidate Projects

### Glorytun

- Repo: https://github.com/angt/glorytun

Glorytun is a multipath UDP tunnel and is used in the OpenMPTCProuter ecosystem. Its README calls out multipath/failover, encrypted/authenticated traffic, path MTU handling, and traffic shaping.

This is interesting because it can be a user-space tunnel rather than "replace the whole router firmware with an MPTCP kernel." That makes it a better candidate for a GL.iNet package experiment.

### MLVPN

- Site: https://zehome.github.io/MLVPN/
- Repo: https://github.com/zehome/MLVPN

MLVPN is explicitly a multi-link VPN. Its stated goals are bonding links for increased bandwidth, monitoring/removing faulty links without losing TCP connections, and securing traffic to an aggregation server.

The concerns are age, packaging, and whether it behaves well with unequal cellular links without painful tuning.

### UBOND

- Repo: https://github.com/markfoodyburton/ubond

UBOND is a user-mode bonding project derived from MLVPN-style ideas, with reorder-buffer work. It is interesting because reorder buffers are where a lot of real bonding either works or becomes miserable.

Same caution: old project, needs build/testing, not something to throw on the live router without lab work.

### SmoothWAN

- Repo: https://github.com/SmoothWAN/SmoothWAN
- Site: https://smoothwan.com/

SmoothWAN was an OpenWrt bonding distribution around Speedify with browser configuration. The project is now sunset because Speedify officially supports OpenWrt. It is still useful as prior art for UX and router packaging, but it is not the open-source self-hosted answer.

### Engarde

- Repo: https://github.com/porech/engarde

Engarde is closer to redundant mode than bandwidth aggregation. It replicates packets across connections for stability, not higher throughput. For livestream reliability, that can matter. For "make two 80 Mbps uploads act like one 160 Mbps pipe," it is not the main answer.

### TinyFEC VPN

- Repo: https://github.com/wangyu-/tinyfecVPN

TinyFEC VPN helps lossy links using forward error correction. Useful conceptually, especially for cellular, but it is not a multi-WAN bonding system by itself.

### Tailscale

Tailscale exit nodes are excellent for simple private-network routing, but they do not currently do Speedify-style multipath bonding. Tailscale docs describe direct, DERP relay, and peer relay connection types, plus HA/failover behavior for overlapping connectors, but that is still failover/routing selection, not one flow split across multiple WANs.

There is a Tailscale feature request for multipath/single-flow traffic:

- https://github.com/tailscale/tailscale/issues/18221

That request describes almost exactly the desired product shape: multiple encrypted sessions to an exit node, with reassembly at the server. So the idea is not weird. It is just not a small Tailscale plugin today.

## Home Fiber Exit Node Feasibility

This is reasonable if the home connection is truly fast enough and reachable.

Good setup:

- symmetric fiber at home
- public IP or reliable port-forwarding
- wired home server
- server geographically reasonable relative to the field site and CDN
- router has enough CPU for tunnel encryption/encapsulation

Bad setup:

- cable internet with weak upstream
- CGNAT at home with no inbound reachability
- high-latency path from event site to home
- home server on Wi-Fi
- router CPU already close to max

For your upload-to-CDN use case, the home server becomes the egress point. So the event router uploads into the bonded tunnel, the home fiber server reassembles it, and then the home fiber uploads to the CDN.

That only helps if home fiber upload is comfortably higher than the combined cellular upload. If the home uplink is the bottleneck, congrats, we built a very elaborate funnel.

## Best Architecture For This Project

I would not try to make Tailscale itself do this first.

The realistic path is:

1. Keep `wan-split` as the safe router-control/dashboard layer.
2. Prototype true bonding on separate lab hardware with OpenMPTCProuter plus a VPS or home fiber server.
3. Measure CPU, latency, MTU, packet loss, and upload behavior under the exact "many devices to one CDN" workflow.
4. If OpenMPTCProuter works well, decide whether to:
   - run it on a dedicated small box in front of/behind the GL.iNet router
   - build an image for compatible GL.iNet hardware
   - borrow the server/client pieces and package a smaller GL.iNet add-on
5. If full OMR is too heavy, try a user-space tunnel path:
   - Glorytun UDP first
   - MLVPN/UBOND second
   - wrap with the same dashboard/kill-switch style we already built

## What A Minimal Product Could Look Like

Router UI:

- select 2-3 WANs
- set exit server address
- show per-path latency/loss/rate
- enable bonding
- disable bonding and return to normal GL.iNet routing

Server installer:

```sh
curl -fsSL https://example/install-bond-exit.sh | sh
```

Router package:

```sh
opkg install glinet-bond-client
```

Control plane:

- first version: plain server IP + generated key
- later version: Tailscale for discovery/management only
- data plane: purpose-built bonding tunnel, not Tailscale WireGuard

## Recommendation

For tomorrow's small-scale deployment, do not use true bonding.

Use the new `wan-split` throughput mode if we want smarter client assignment, because it has a fast kill switch and does not replace the router's firmware.

For the next project, start with OpenMPTCProuter in a lab. It is the closest existing open-source system to the thing you described. If it works well but is too heavy for the X2000, the forkable path is probably not "fork Tailscale." It is "extract or wrap an OMR-style user-space tunnel stack and give it the GL.iNet/iPad-friendly UX this project already has."
