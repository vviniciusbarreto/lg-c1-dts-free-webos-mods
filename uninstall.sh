#!/bin/sh
# Removes everything install.sh added. Does not touch dts_restore_plus.
I=/var/lib/webosbrew/init.d
rm -f "$I/00-dts-early" "$I/dts_badge" "$I/earc_fix"
for p in /proc/[0-9]*; do   # stop the badge watcher and the eARC fix (every copy)
  case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in
    "/bin/sh /var/lib/webosbrew/dts_badge/"*) kill "${p#/proc/}" 2>/dev/null ;;
  esac
done
rm -rf /var/lib/webosbrew/dts_badge /run/dts_badge
rm -f /tmp/dts_badge.log /tmp/dts_badge.log.tmp /tmp/dts_badge.pid /tmp/dts_badge.prev /tmp/dts_badge.prev.tmp /tmp/dts_badge.prev.key /tmp/earc_fix.log   # older versions
echo "Removed. (dts_restore_plus is still installed; use its own uninstall.sh to remove it.)"
