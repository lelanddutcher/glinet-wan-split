#!/bin/sh
set -eu

if [ "$(id -u)" != "0" ]; then
	echo "Run as root on the router." >&2
	exit 1
fi

if [ -x /usr/bin/wan-split ]; then
	/usr/bin/wan-split off || true
fi

rm -f /usr/bin/wan-split
rm -f /etc/wan-split.conf
rm -f /etc/init.d/wan-split
rm -f /etc/hotplug.d/iface/95-wan-split
rm -rf /www/wan-split
rm -f /www/cgi-bin/wan-split-control

echo "Removed wan-split files."

