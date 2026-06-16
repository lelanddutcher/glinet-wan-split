#!/bin/sh
set -eu

CMD=${WAN_SPLIT_CMD:-/usr/bin/wan-split}
BASE=${WAN_SPLIT_SHADOW_BASE:-/tmp/wan-split-shadow}
CONF="$BASE.conf"
LEASES="$BASE.leases"
STATE="$BASE-state"
PRIO=${WAN_SPLIT_SHADOW_PRIO:-25400}
TABLE_BASE=${WAN_SPLIT_SHADOW_TABLE_BASE:-20100}
TARGET=${WAN_SPLIT_SHADOW_TARGET:-8.8.8.8}

CLIENTS=

cleanup() {
	WAN_SPLIT_CONFIG="$CONF" "$CMD" off >/dev/null 2>&1 || true
	ip rule show | grep -q "^$PRIO:" && while ip rule show | grep -q "^$PRIO:"; do
		ip rule del priority "$PRIO" 2>/dev/null || break
	done
	for n in 0 1 2 3 4; do
		ip route flush table $((TABLE_BASE + n)) >/dev/null 2>&1 || true
	done
}

trap cleanup EXIT

write_leases() {
	count="$1"
	: > "$LEASES"
	i=1
	CLIENTS=
	while [ "$i" -le "$count" ]; do
		last=$((200 + i))
		CLIENTS="$CLIENTS $last"
		suffix="$(printf '%02x' "$i")"
		printf '1781609466 aa:bb:cc:dd:ee:%s 192.168.7.%s cam%s 01:aa\n' "$suffix" "$last" "$last" >> "$LEASES"
		i=$((i + 1))
	done
}

write_conf() {
	interfaces="$1"
	cat > "$CONF" <<EOF
ENABLED=0
INTERFACES="$interfaces"
PRIO=$PRIO
TABLE_BASE=$TABLE_BASE
ASSIGNMENT_MODE=balanced
HEALTH_CHECK=1
HEALTH_TARGETS="1.1.1.1 8.8.8.8"
HEALTH_COUNT=1
HEALTH_TIMEOUT=2
HOTPLUG_REBALANCE=0
EXCLUDE_IPS=""
LEASE_FILE="$LEASES"
STATE_DIR="$STATE"
LOG_FILE="$BASE.log"
EOF
}

assignment_counts() {
	assign="$STATE/assignments"
	if [ ! -f "$assign" ]; then
		echo "assignments: none"
		return
	fi
	echo "assignments by WAN:"
	awk '{ count[$4]++ } END { for (wan in count) print "  " wan, count[wan] }' "$assign" | sort
}

route_counts() {
	tmp="$BASE.routes"
	: > "$tmp"
	for last in $CLIENTS; do
		ip="192.168.7.$last"
		ip route get "$TARGET" from "$ip" iif br-lan | head -n 1 >> "$tmp"
	done
	echo "route lookups:"
	sed 's/^/  /' "$tmp"
	echo "routes by device:"
	awk '
		{
			for (i = 1; i <= NF; i++) {
				if ($i == "dev") {
					count[$(i + 1)]++
				}
			}
		}
		END {
			for (dev in count) print "  " dev, count[dev]
		}
	' "$tmp" | sort
}

run_case() {
	name="$1"
	interfaces="$2"
	echo
	echo "### CASE: $name"
	write_conf "$interfaces"
	WAN_SPLIT_CONFIG="$CONF" "$CMD" dry-run
	if WAN_SPLIT_CONFIG="$CONF" "$CMD" on; then
		assignment_counts
		route_counts
	else
		echo "apply returned non-zero"
		echo "remaining shadow rules:"
		ip rule show | grep "^$PRIO:" || echo "  none"
	fi
}

echo "shadow test started: $(date)"
echo "using prio=$PRIO table_base=$TABLE_BASE target=$TARGET"

write_leases 12
run_case "two WANs, 12 clients" "tethering modem_2_1"
write_leases 8
run_case "client churn, 8 clients" "tethering modem_2_1"
write_leases 13
run_case "client churn, 13 clients" "tethering modem_2_1"
write_leases 12
run_case "tethering only, 12 clients" "tethering"
run_case "cellular only, 12 clients" "modem_2_1"
run_case "no active WANs" "wan secondwan wwan"

cleanup
echo
echo "cleanup verification:"
ip rule show | grep "^$PRIO:" || echo "  no shadow rules"
echo "shadow test completed: $(date)"
