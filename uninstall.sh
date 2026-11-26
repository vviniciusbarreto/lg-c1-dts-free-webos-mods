#!/bin/sh
# Removes everything install.sh added. Does not touch dts_restore_plus.
I=/var/lib/webosbrew/init.d
rm -f "$I/00-dts-early" "$I/dts_badge" "$I/earc_fix"
for p in /proc/[0-9]*; do   # stop the badge watcher and the eARC fix (every copy)
  case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in
    "/bin/sh /var/lib/webosbrew/dts_badge/"*) kill "${p#/proc/}" 2>/dev/null ;;
  esac
done
# put back the PCM renderer's metadata type if a DTS film left it at 0
v=$(cat /run/dts_badge/renderer-metadata-type 2>/dev/null)
if [ -n "$v" ]; then
  id=$(sed -n 's/.*](\([0-9]*\)).*/\1/p' /proc/aaudio/module/PCMREN_P0/status 2>/dev/null | head -n 1)
  for d in /proc/aaudio/instances/*; do timeout -t 2 grep -qx "id=(int)$id" "$d/prop" 2>/dev/null && { echo "0x64040004 $v" > "$d/cmd"; break; }; done
fi
rm -rf /var/lib/webosbrew/dts_badge /run/dts_badge
rm -f /tmp/dts_badge.log /tmp/dts_badge.log.tmp /tmp/dts_badge.pid /tmp/dts_badge.prev /tmp/dts_badge.prev.tmp /tmp/dts_badge.prev.key /tmp/earc_fix.log   # older versions
echo "Removed. (dts_restore_plus is still installed; use its own uninstall.sh to remove it.)"
