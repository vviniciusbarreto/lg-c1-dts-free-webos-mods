#!/bin/sh
# Installs the audio badges (DTS / Dolby), the post-boot eARC fix and the early DTS hook.
# Run on the TV as root (ssh), from this folder:  sh install.sh
# Requires: a rooted LG webOS TV with Homebrew Channel (webosbrew) and dts_restore_plus already installed.
set -e
D=/var/lib/webosbrew/dts_badge
I=/var/lib/webosbrew/init.d
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "Run as root."; exit 1; }
[ -d "$I" ] || { echo "$I not found: is webosbrew (Homebrew Channel) installed?"; exit 1; }
if [ ! -x /var/lib/webosbrew/dts_restore/init_dts.sh ]; then
  echo "dts_restore_plus not found (/var/lib/webosbrew/dts_restore)."
  echo "Install it first: https://github.com/josippapez/dts_restore_plus"
  exit 1
fi

mkdir -p "$D"
cp -f "$HERE/files/dts_badge.sh" "$HERE/files/earc_fix.sh" "$D/"
chmod 755 "$D/dts_badge.sh" "$D/earc_fix.sh"
if [ -f "$HERE/dts_icon.png" ]; then cp -f "$HERE/dts_icon.png" "$D/dts_icon.png"; chmod 644 "$D/dts_icon.png"
else echo "Note: no dts_icon.png next to install.sh; the DTS badge will show text only (see README, 'DTS icon')."; fi

# The TV's log library cuts the messages of the services on its "blacklist" when they log a lot
# (NL_LOG_BLOCKED); audiooutputd and audiod are on it, and the badges read their lines. Take only those two
# off the writable copy of the list (the read-only one in /etc stays as it is); uninstall.sh puts it back.
BL=/mnt/lg/cmn_data/whitelist/blacklist.txt
if [ -f "$BL" ] && grep -q -x -E "audiooutputd|audiod" "$BL"; then
  [ -f "$D/blacklist.txt.orig" ] || cp -p "$BL" "$D/blacklist.txt.orig"
  grep -v -x -E "audiooutputd|audiod" "$BL" > "$BL.tmp" && cat "$BL.tmp" > "$BL"; rm -f "$BL.tmp"
  echo "Log blacklist: audiooutputd and audiod taken off (takes effect after a reboot)."
fi

for f in 00-dts-early dts_badge earc_fix; do cp -f "$HERE/files/init.d/$f" "$I/$f"; chmod 755 "$I/$f"; done

# (re)start the badge watcher now; a new one stops any running copy (the eARC fix only makes sense at boot)
rm -f /run/dts_badge/dts_badge.pid
setsid nohup "$D/dts_badge.sh" </dev/null >/dev/null 2>&1 &
echo "Installed. Logs: /run/dts_badge/dts_badge.log  |  eARC fix (after next boot): /run/dts_badge/earc_fix.log"
