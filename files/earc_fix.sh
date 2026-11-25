#!/bin/sh
# Post-boot eARC fix. On the LG C1, after a cold boot the eARC link sometimes comes up without finishing
# the sync with the soundbar (arcProfile empty, no "sound_mode_sync"), and DTS passthrough turns into noise.
# Toggling "eARC Support" off and on fixes it; this script does that once per boot and checks the result.
# Turn off: touch /var/lib/webosbrew/dts_badge/disabled_earc_fix
DIR=/var/lib/webosbrew/dts_badge
DBG=/tmp/var/log/dbg-log
LOG=/tmp/earc_fix.log
log() { echo "$(date -u '+%F %T') $*" >> "$LOG"; }
get() { timeout -t 10 luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings "{\"category\":\"sound\",\"keys\":[\"$1\"]}" </dev/null 2>/dev/null | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"; }
set_earc() { timeout -t 10 luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings "{\"category\":\"sound\",\"settings\":{\"eArcSupport\":\"$1\"}}" </dev/null 2>&1; }
synced() { tail -n 3000 "$DBG" 2>/dev/null | grep "sendArcState" | tail -n 1 | grep -q "arcActivation\[eARC\].*audioDeviceType\[sound_mode_sync\]"; }

[ -f "$DIR/disabled_earc_fix" ] && { log "disabled (disabled_earc_fix)"; exit 0; }
log "started (pid $$)"

# Let the TV settle: uptime >= 60 s and sound output on ARC/eARC (at most ~5 min).
i=0
while [ $i -lt 60 ]; do
  up=$(cut -d. -f1 /proc/uptime)
  if [ "$up" -ge 60 ] && [ "$(get soundOutput)" = "external_arc" ]; then break; fi
  sleep 5; i=$((i+1))
done
if [ "$(get soundOutput)" != "external_arc" ]; then log "sound output is not external_arc - nothing to do"; exit 0; fi
if [ "$(get eArcSupport)" != "on" ]; then log "eArcSupport is not on - nothing to do"; exit 0; fi

n=0
while [ $n -lt 3 ]; do
  n=$((n+1))
  log "attempt $n: eArcSupport off -> on"
  log "off: $(set_earc off)"
  sleep 3
  log "on: $(set_earc on)"
  sleep 15
  if synced; then log "OK: eARC synced (sound_mode_sync)"; exit 0; fi
  log "still no sound_mode_sync"
done
log "gave up after $n attempts"
exit 0
