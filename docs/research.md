# Research Notes: Cheap Multi-WAN For Same-Destination Workloads

This project is for a narrow gap between ordinary failover/load balancing and true bonding.

Ordinary GL.iNet/OpenWrt-style load balancing is usually per connection. True bonding needs a cooperating server, tunnel, MPTCP, MPUDP, Speedify, Peplink SpeedFusion, GL AstroWarp, or similar aggregation layer. `wan-split` sits in the middle: it spreads many client devices across WANs by source IP.

## Primary Vendor Context

- GL.iNet Multi-WAN docs: Load Balance assigns interfaces to new connections based on configured ratio, while active traffic is not guaranteed to match the ratio immediately.
  - https://docs.gl-inet.com/router/en/4/interface_guide/multi-wan/
- GL.iNet forum, "Speed throttled in Multi-WAN Load Balance with VLANs on WAN port": GL staff note that the same website or application typically uses only one interface in Load Balance mode, so bandwidth is not aggregated.
  - https://forum.gl-inet.com/t/speed-throttled-in-multi-wan-load-balance-with-vlans-on-wan-port-gl-be3600-slate-7/67624
- GL.iNet forum, "Clarification about the Load Balance feature": user expected link aggregation on a GL-X3000; replies clarify that WAN link aggregation needs a server and that a single stream will not exceed the fastest single link.
  - https://forum.gl-inet.com/t/clarification-about-the-load-balance-feature/44565
- GL.iNet forum, "WAN Bonding?": community answer explains that `mwan3` still performs connection-based load balancing and does not combine ISP links for one faster connection.
  - https://forum.gl-inet.com/t/wan-bonding/11765
- OpenWrt `mwan3` package config: the stock example has weighted members, balanced policies, health-tracked interfaces, and sticky HTTPS rules. It is a mature package, but it is still policy/load-balancing machinery, not magic single-flow bonding.
  - https://github.com/openwrt/packages/tree/master/net/mwan3
- GL.iNet forum posts on `kmwan` and `mwan3`: newer GL firmware uses `kmwan` for the GL GUI Multi-WAN feature, and GL staff commonly advise disabling `kmwan` before using `mwan3` to avoid conflicts.
  - https://forum.gl-inet.com/t/multi-wan-failover-stuck-on-lower-priority-interface/59096
  - https://forum.gl-inet.com/t/multiwan-settings-per-device/47443
  - https://forum.gl-inet.com/t/mwan3-installation-on-flint-4-8-3-is-cutting-off-internet-access/66295/4

## People Looking For This Shape

These are useful places to answer carefully with a "this is not bonding, but may help if you have many clients" framing.

- GL.iNet forum: GL-MT6000 Load Balance help
  - https://forum.gl-inet.com/t/gl-mt6000-flint-2-load-balance-help/51234
  - User wanted specific clients mapped to specific uplinks. GL staff described this as policy routing and said stock GL firmware did not support it at that moment.
- GL.iNet forum: Load Balance focuses on upload speed
  - https://forum.gl-inet.com/t/load-balance-focuses-on-upload-speed/43247
  - User wanted upload aggregation. Replies explain ordinary load balancing cannot move one stream over multiple links and that bonding needs server-side aggregation.
- GL.iNet forum: Multi WAN and dynamic DNS
  - https://forum.gl-inet.com/t/multi-wan-and-dynamic-dns-on-gl-mt6000/47268
  - Discussion says load balancing is most acceptable when one device is routed via WAN1 and another via WAN2, which is exactly this project's source-client approach.
- Reddit r/GlInet: 2nd GL.iNET router in AP mode + Multi-WAN + Load Balance
  - https://www.reddit.com/r/GlInet/comments/1u131ri/2nd_glinet_router_in_ap_mode_multiwan_load/
  - User is confused by the GL UI note that same application/site usually uses one interface and asks whether Load Balance can increase speed.
- Reddit r/GlInet: How to Route High-Bandwidth Devices to Faster WAN on GL-MT6000?
  - https://www.reddit.com/r/GlInet/comments/1dv66ju/how_to_route_highbandwidth_devices_to_faster_wan/
  - User has high-bandwidth devices and wants specific clients routed to a faster WAN, which is the same policy-routing shape even if their goal is preference instead of even distribution.
- Reddit r/GlInet: GL-BE9300 DMZ and inbound traffic failing with Multi-WAN Load Balancing
  - https://www.reddit.com/r/GlInet/comments/1q7jjis/glbe9300_v4x_dmz_and_inbound_traffic_failing_with/
  - User asks for policy/sticky behavior because load balancing sends return traffic out a different WAN. Not this exact upload use case, but closely related source/interface policy routing pain.
- Reddit r/GlInet: Combining two GL-X3000
  - https://www.reddit.com/r/GlInet/comments/1f45hjt/combining_two_glx3000/
  - User considers multiple GL-X3000/Starlink links and asks about load balance or bond. Replies clarify load balancing spreads devices but does not combine links into one faster access path.
- Reddit r/openwrt: Budget hardware recommendations for portable router
  - https://www.reddit.com/r/openwrt/comments/1iyqpxn/budget_hardware_recommendations_for_portable/
  - IRL streamer used multiple cellular WANs and Speedify/MWAN3 but was looking for portable hardware and reliable failover. Useful audience overlap for field production networking.

## Good Outreach Framing

Use this phrasing when replying to people:

> This will not bond one connection. If your problem is one upload/speedtest/VPN needing the sum of all WANs, you still need tunnel bonding or MPTCP-style aggregation. But if you have many devices all uploading to the same destination, this can spread whole clients across WANs with source-IP policy routing and gives you a simple LAN dashboard/kill switch.

## Search Phrases That Surface Similar Users

- "GL.iNet same application or site will usually only use one interface"
- "GL.iNet load balance policy routing clients WAN"
- "GL.iNet load balance upload speed"
- "mwan3 same destination one WAN"
- "cheap multi wan cellular load balance upload"
- "IRL streamer OpenWrt mwan3 cellular failover"
- "multi WAN same CDN upload"
- "load balance many devices same website"
