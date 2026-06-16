#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wan-split-acct-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

MOCKBIN="$WORK/bin"
mkdir -p "$MOCKBIN" "$WORK/state"

cat > "$WORK/leases" <<'EOF'
1781609466 aa:aa:aa:aa:aa:01 192.168.7.101 cam01 01:aa
1781609466 aa:aa:aa:aa:aa:02 192.168.7.102 cam02 01:aa
EOF

cat > "$WORK/conf" <<EOF
ENABLED=0
INTERFACES="tethering modem_2_1"
PRIO=25300
TABLE_BASE=20010
ASSIGNMENT_MODE=throughput
WAN_CAPACITY_MBPS="tethering:80 modem_2_1:40"
WAN_CAPACITY_DEFAULT_MBPS=60
ACCOUNTING=1
ACCOUNTING_CHAIN=WAN_SPLIT_ACCT
CLIENT_RATE_ALPHA=0
MIN_SAMPLE_SECONDS=1
HEALTH_CHECK=0
HOTPLUG_REBALANCE=1
EXCLUDE_IPS=""
LEASE_FILE="$WORK/leases"
STATE_DIR="$WORK/state"
LOG_FILE="$WORK/log"
EOF

cat > "$MOCKBIN/date" <<'EOF'
#!/bin/sh
if [ "$1" = "+%s" ]; then
	cat "$MOCK_NOW_FILE"
else
	/bin/date "$@"
fi
EOF
chmod +x "$MOCKBIN/date"

cat > "$MOCKBIN/ip" <<'EOF'
#!/bin/sh
if [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$3" = "show" ]; then
	case "$5" in
		br-lan) echo "    inet 192.168.7.1/24 brd 192.168.7.255 scope global br-lan" ;;
	esac
	exit 0
fi
exit 0
EOF
chmod +x "$MOCKBIN/ip"

cat > "$MOCKBIN/iptables" <<'EOF'
#!/bin/sh
echo "iptables $*" >> "$MOCK_IPTABLES_LOG"
case "$*" in
	*"-C PREROUTING"*) [ -f "$MOCK_JUMP_PRESENT" ] && exit 0 || exit 1 ;;
	*"-I PREROUTING"*) touch "$MOCK_JUMP_PRESENT"; exit 0 ;;
	*"-D PREROUTING"*) rm -f "$MOCK_JUMP_PRESENT"; exit 0 ;;
	*"-C WAN_SPLIT_ACCT"*) exit 1 ;;
esac
exit 0
EOF
chmod +x "$MOCKBIN/iptables"

cat > "$MOCKBIN/iptables-save" <<'EOF'
#!/bin/sh
cat "$MOCK_COUNTERS_FILE"
EOF
chmod +x "$MOCKBIN/iptables-save"

export PATH="$MOCKBIN:$PATH"
export MOCK_NOW_FILE="$WORK/now"
export MOCK_COUNTERS_FILE="$WORK/counters"
export MOCK_IPTABLES_LOG="$WORK/iptables.log"
export MOCK_JUMP_PRESENT="$WORK/jump-present"
: > "$MOCK_IPTABLES_LOG"

cat > "$WORK/counters" <<'EOF'
[10:1000] -A WAN_SPLIT_ACCT -s 192.168.7.101/32 -j RETURN
[20:2000] -A WAN_SPLIT_ACCT -s 192.168.7.102/32 -j RETURN
EOF
echo 100 > "$WORK/now"
WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" sample > "$WORK/sample1.out"
grep -q "192.168.7.101 rate_bps=0" "$WORK/sample1.out"
grep -q "192.168.7.102 rate_bps=0" "$WORK/sample1.out"

cat > "$WORK/counters" <<'EOF'
[110:1001000] -A WAN_SPLIT_ACCT -s 192.168.7.101/32 -j RETURN
[220:2002000] -A WAN_SPLIT_ACCT -s 192.168.7.102/32 -j RETURN
EOF
echo 110 > "$WORK/now"
WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" sample > "$WORK/sample2.out"
grep -q "192.168.7.101 rate_bps=800000" "$WORK/sample2.out"
grep -q "192.168.7.102 rate_bps=1600000" "$WORK/sample2.out"

grep -q 'iptables -t mangle -A WAN_SPLIT_ACCT -s 192.168.7.101/32 -j RETURN' "$MOCK_IPTABLES_LOG"
grep -q 'iptables -t mangle -A WAN_SPLIT_ACCT -s 192.168.7.102/32 -j RETURN' "$MOCK_IPTABLES_LOG"

WAN_SPLIT_CONFIG="$WORK/conf" "$ROOT/files/usr/bin/wan-split" off > "$WORK/off.out"
grep -q 'iptables -t mangle -D PREROUTING -i br-lan -j WAN_SPLIT_ACCT' "$MOCK_IPTABLES_LOG"
grep -q 'iptables -t mangle -F WAN_SPLIT_ACCT' "$MOCK_IPTABLES_LOG"
grep -q 'iptables -t mangle -X WAN_SPLIT_ACCT' "$MOCK_IPTABLES_LOG"
[ ! -f "$WORK/state/client-rates" ]

echo "accounting tests passed"
