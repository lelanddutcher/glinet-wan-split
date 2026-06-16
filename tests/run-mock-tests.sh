#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wan-split-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

MOCKBIN="$WORK/bin"
mkdir -p "$MOCKBIN" "$WORK/state"

cat > "$WORK/leases" <<'EOF'
1781609466 aa:aa:aa:aa:aa:01 192.168.7.101 cam01 01:aa
1781609466 aa:aa:aa:aa:aa:02 192.168.7.102 cam02 01:aa
1781609466 aa:aa:aa:aa:aa:03 192.168.7.103 cam03 01:aa
1781609466 aa:aa:aa:aa:aa:04 192.168.7.104 cam04 01:aa
1781609466 aa:aa:aa:aa:aa:05 192.168.7.105 cam05 01:aa
1781609466 aa:aa:aa:aa:aa:06 192.168.7.106 cam06 01:aa
1781609466 aa:aa:aa:aa:aa:07 192.168.7.107 cam07 01:aa
1781609466 aa:aa:aa:aa:aa:08 192.168.7.108 cam08 01:aa
1781609466 aa:aa:aa:aa:aa:09 192.168.7.109 cam09 01:aa
1781609466 aa:aa:aa:aa:aa:0a 192.168.7.110 cam10 01:aa
1781609466 aa:aa:aa:aa:aa:0b 192.168.7.111 cam11 01:aa
1781609466 aa:aa:aa:aa:aa:0c 192.168.7.112 cam12 01:aa
1781609466 aa:aa:aa:aa:aa:04 192.168.9.104 guest01 01:aa
EOF

cat > "$WORK/conf" <<EOF
ENABLED=0
INTERFACES="tethering modem_2_1 wan secondwan wwan"
PRIO=25300
TABLE_BASE=20010
ASSIGNMENT_MODE=balanced
HEALTH_CHECK=1
HEALTH_TARGETS="1.1.1.1 8.8.8.8"
HEALTH_COUNT=1
HEALTH_TIMEOUT=1
HOTPLUG_REBALANCE=1
EXCLUDE_IPS=""
LEASE_FILE="$WORK/leases"
STATE_DIR="$WORK/state"
LOG_FILE="$WORK/log"
EOF

cat > "$MOCKBIN/ifstatus" <<'EOF'
#!/bin/sh
case "$1" in
	tethering)
		cat <<JSON
{"up":true,"l3_device":"eth2","device":"eth2"}
JSON
		;;
	modem_2_1)
		cat <<JSON
{"up":true,"l3_device":"wwan0_1","device":"wwan0_1"}
JSON
		;;
	wan)
		if [ "${MOCK_WAN3_UP:-0}" = "1" ]; then
			cat <<JSON
{"up":true,"l3_device":"eth1","device":"eth1"}
JSON
		else
			cat <<JSON
{"up":false,"device":"wan"}
JSON
		fi
		;;
	*)
		cat <<JSON
{"up":false,"device":"$1"}
JSON
		;;
esac
EOF
chmod +x "$MOCKBIN/ifstatus"

cat > "$MOCKBIN/jsonfilter" <<'EOF'
#!/bin/sh
expr=
while [ "$#" -gt 0 ]; do
	case "$1" in
		-e) shift; expr="$1" ;;
	esac
	shift || true
done
data="$(cat)"
case "$expr" in
	'@.up')
		echo "$data" | sed -n 's/.*"up":\([^,}]*\).*/\1/p'
		;;
	'@.l3_device')
		echo "$data" | sed -n 's/.*"l3_device":"\([^"]*\)".*/\1/p'
		;;
	'@.device')
		echo "$data" | sed -n 's/.*"device":"\([^"]*\)".*/\1/p'
		;;
	*)
		exit 1
		;;
esac
EOF
chmod +x "$MOCKBIN/jsonfilter"

cat > "$MOCKBIN/ip" <<'EOF'
#!/bin/sh
echo "ip $*" >> "$MOCK_IP_LOG"

if [ "$1" = "-4" ] && [ "$2" = "route" ] && [ "$3" = "show" ]; then
	shift 3
	case "$*" in
		"dev br-lan scope link")
			echo "192.168.7.0/24 dev br-lan scope link src 192.168.7.1"
			;;
			"default dev eth2")
				echo "default via 198.51.100.1 dev eth2 proto static src 198.51.100.10 metric 30"
				;;
			"default dev wwan0_1")
				echo "default via 203.0.113.1 dev wwan0_1 proto static src 203.0.113.10 metric 40"
				;;
			"default dev eth1")
				echo "default via 192.0.2.1 dev eth1 proto static src 192.0.2.10 metric 20"
				;;
		*)
			echo "default proto static"
			echo "192.168.7.0/24 dev br-lan scope link src 192.168.7.1"
			;;
	esac
	exit 0
fi

if [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$3" = "show" ]; then
	case "$5" in
		br-lan) echo "    inet 192.168.7.1/24 brd 192.168.7.255 scope global br-lan" ;;
			eth2) echo "    inet 198.51.100.10/24 brd 198.51.100.255 scope global eth2" ;;
			wwan0_1) echo "    inet 203.0.113.10/24 brd 203.0.113.255 scope global wwan0_1" ;;
			eth1) echo "    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth1" ;;
	esac
	exit 0
fi

if [ "$1" = "rule" ] && [ "$2" = "show" ]; then
	echo "0:	from all lookup local"
	echo "5270:	from all lookup 52"
	echo "32766:	from all lookup main"
	exit 0
fi

exit 0
EOF
chmod +x "$MOCKBIN/ip"

cat > "$MOCKBIN/ping" <<'EOF'
#!/bin/sh
src=
while [ "$#" -gt 0 ]; do
	case "$1" in
		-I) shift; src="$1" ;;
	esac
	shift || true
done
case " ${MOCK_PING_FAIL_SRC:-} " in
	*" $src "*) exit 1 ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/ping"

export PATH="$MOCKBIN:$PATH"
export MOCK_IP_LOG="$WORK/ip.log"
: > "$MOCK_IP_LOG"

WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" dry-run > "$WORK/dry-run.out"
grep -q "tethering table=20010 dev=eth2" "$WORK/dry-run.out"
grep -q "modem_2_1 table=20011 dev=wwan0_1" "$WORK/dry-run.out"
grep -q "192.168.7.101" "$WORK/dry-run.out"
! grep -q "192.168.9.104" "$WORK/dry-run.out"
[ "$(grep -c -- '-> tethering' "$WORK/dry-run.out")" -eq 6 ]
[ "$(grep -c -- '-> modem_2_1' "$WORK/dry-run.out")" -eq 6 ]

WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" on > "$WORK/on.out"
grep -q '^ENABLED=0$' "$WORK/conf"
[ -f "$WORK/state/enabled" ]
[ "$(grep -c 'ip rule add from 192.168.7.' "$MOCK_IP_LOG")" -eq 12 ]
grep -q 'ip route add default via 198.51.100.1 dev eth2 src 198.51.100.10 table 20010' "$MOCK_IP_LOG"
grep -q 'ip route add default via 203.0.113.1 dev wwan0_1 src 203.0.113.10 table 20011' "$MOCK_IP_LOG"

MOCK_PING_FAIL_SRC="198.51.100.10" WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" dry-run > "$WORK/tether-down.out"
! grep -q "tethering table=20010" "$WORK/tether-down.out"
grep -q "modem_2_1 table=20011 dev=wwan0_1" "$WORK/tether-down.out"
[ "$(grep -c -- '-> modem_2_1' "$WORK/tether-down.out")" -eq 12 ]

MOCK_PING_FAIL_SRC="198.51.100.10 203.0.113.10" WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" dry-run > "$WORK/all-down.out"
grep -q "Active WANs:" "$WORK/all-down.out"
grep -q "  none" "$WORK/all-down.out"

WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" off > "$WORK/off.out"
grep -q '^ENABLED=0$' "$WORK/conf"
[ ! -f "$WORK/state/enabled" ]
grep -q 'ip rule del from 192.168.7.101/32' "$MOCK_IP_LOG"

cat > "$WORK/throughput.conf" <<EOF
ENABLED=0
INTERFACES="tethering modem_2_1 wan"
PRIO=25300
TABLE_BASE=20010
ASSIGNMENT_MODE=throughput
WAN_CAPACITY_MBPS="tethering:80 modem_2_1:40 wan:120"
WAN_CAPACITY_DEFAULT_MBPS=60
ACCOUNTING=0
CLIENT_RATE_HINTS="192.168.7.101:90000000 192.168.7.102:70000000 192.168.7.103:50000000 192.168.7.104:5000000 192.168.7.105:5000000 192.168.7.106:5000000 192.168.7.107:5000000 192.168.7.108:5000000 192.168.7.109:5000000 192.168.7.110:5000000 192.168.7.111:5000000 192.168.7.112:5000000"
HEALTH_CHECK=1
HEALTH_TARGETS="1.1.1.1 8.8.8.8"
HEALTH_COUNT=1
HEALTH_TIMEOUT=1
HOTPLUG_REBALANCE=1
EXCLUDE_IPS=""
LEASE_FILE="$WORK/leases"
STATE_DIR="$WORK/state-throughput"
LOG_FILE="$WORK/log-throughput"
EOF
mkdir -p "$WORK/state-throughput"
MOCK_WAN3_UP=1 WAN_SPLIT_CONFIG="$WORK/throughput.conf" "$ROOT/files/usr/bin/wan-split" dry-run > "$WORK/throughput.out"
grep -q "wan table=20012 dev=eth1" "$WORK/throughput.out"
grep -q "192.168.7.101 .* -> wan table=20012 dev=eth1 rate_bps=90000000" "$WORK/throughput.out"
grep -q "192.168.7.102 .* -> tethering table=20010 dev=eth2 rate_bps=70000000" "$WORK/throughput.out"
grep -q "192.168.7.103 .* -> modem_2_1 table=20011 dev=wwan0_1 rate_bps=50000000" "$WORK/throughput.out"
[ "$(grep -c -- '-> wan' "$WORK/throughput.out")" -gt "$(grep -c -- '-> modem_2_1' "$WORK/throughput.out")" ]

MOCK_WAN3_UP=1 MOCK_PING_FAIL_SRC="192.0.2.10" WAN_SPLIT_CONFIG="$WORK/throughput.conf" "$ROOT/files/usr/bin/wan-split" dry-run > "$WORK/throughput-wan-down.out"
! grep -q "wan table=20012" "$WORK/throughput-wan-down.out"
grep -q "192.168.7.101 .* -> tethering table=20010 dev=eth2 rate_bps=90000000" "$WORK/throughput-wan-down.out"
grep -q "192.168.7.102 .* -> modem_2_1 table=20011 dev=wwan0_1 rate_bps=70000000" "$WORK/throughput-wan-down.out"

echo "mock tests passed"
