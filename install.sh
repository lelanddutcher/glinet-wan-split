#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/wan-split-backup-$STAMP.tar.gz"

if [ "$(id -u)" != "0" ]; then
	echo "Run as root on the router." >&2
	exit 1
fi

paths="
/usr/bin/wan-split
/etc/wan-split.conf
/etc/init.d/wan-split
/etc/hotplug.d/iface/95-wan-split
/www/wan-split/index.html
/www/cgi-bin/wan-split-control
"

existing=""
for path in $paths; do
	if [ -e "$path" ]; then
		existing="$existing $path"
	fi
done

if [ -n "$existing" ]; then
	tar -czf "$BACKUP" $existing
	echo "Backed up existing files to $BACKUP"
fi

mkdir -p /usr/bin
mkdir -p /etc/init.d
mkdir -p /etc/hotplug.d/iface
mkdir -p /www/wan-split
mkdir -p /www/cgi-bin

cp "$ROOT/files/usr/bin/wan-split" /usr/bin/wan-split
cp "$ROOT/files/etc/wan-split.conf" /etc/wan-split.conf
cp "$ROOT/files/etc/init.d/wan-split" /etc/init.d/wan-split
cp "$ROOT/files/etc/hotplug.d/iface/95-wan-split" /etc/hotplug.d/iface/95-wan-split
cp "$ROOT/files/www/wan-split/index.html" /www/wan-split/index.html
cp "$ROOT/files/www/cgi-bin/wan-split-control" /www/cgi-bin/wan-split-control

chmod 0755 /usr/bin/wan-split
chmod 0644 /etc/wan-split.conf
chmod 0755 /etc/init.d/wan-split
chmod 0755 /etc/hotplug.d/iface/95-wan-split
chmod 0644 /www/wan-split/index.html
chmod 0755 /www/cgi-bin/wan-split-control

echo "Installed wan-split."
echo "WAN splitting is not enabled by install."
echo "Next: wan-split dry-run"
echo "Then: wan-split on"

