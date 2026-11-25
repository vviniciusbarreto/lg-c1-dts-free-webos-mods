#!/bin/sh
# Removes everything install.sh added. Does not touch dts_restore_plus.
I=/var/lib/webosbrew/init.d
P=$(cat /tmp/dts_badge.pid 2>/dev/null); [ -n "$P" ] && kill "$P" 2>/dev/null
rm -f "$I/00-dts-early" "$I/dts_badge" "$I/earc_fix" /tmp/dts_badge.pid
rm -rf /var/lib/webosbrew/dts_badge
echo "Removed. (dts_restore_plus is still installed; use its own uninstall.sh to remove it.)"
