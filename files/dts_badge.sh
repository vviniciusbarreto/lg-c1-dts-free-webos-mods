#!/bin/sh
# Audio badges in LG's native style (the "light" toast LG itself uses for HDR / Dolby Vision):
#  - DTS: follows the decision dts_restore_plus' dtsdec writes to /run/dtsc1/last-decision.
#  - Dolby Digital / Dolby Digital Plus / Dolby Atmos: follows the audio "setDecodeInfo" lines in the dbg-log.
# Turn all badges off:      touch /var/lib/webosbrew/dts_badge/disabled
#  - HDMI inputs (e.g. a console): follows audiooutputd's "setAudioInputInfo" lines (sourceType HDMI).
# Turn Dolby badges off:    touch /var/lib/webosbrew/dts_badge/disabled_dolby
# Turn HDMI badges off:     touch /var/lib/webosbrew/dts_badge/disabled_hdmi
DIR=/var/lib/webosbrew/dts_badge
DEC=/run/dtsc1/last-decision
DBG=/tmp/var/log/dbg-log
LOG=/tmp/dts_badge.log
ICON=$DIR/dts_icon.png
DOLBY_ICON=/usr/share/pqcontroller/images/light_toast_icon_dolby.png   # LG's own icon, already on the TV
PIDF=/tmp/dts_badge.pid

log() { # the log lives in /tmp; past 64 KB only its tail is kept
  [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 65536 ] && { tail -n 200 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }
  echo "$(date -u '+%F %T') $*" >> "$LOG"; }

toast() { # $1 = text, $2 = icon (without the icon file the badge shows text only)
  ic=""; [ -f "$2" ] && ic="\"iconUrl\":\"$2\","
  timeout -t 10 luna-send -n 1 luna://com.webos.notification/createToast \
    "{\"sourceId\":\"com.webos.service.pqcontroller\",\"message\":\"$1\",${ic}\"noaction\":true,\"type\":\"light\"}" </dev/null 2>&1
}

line_age() { # $1 = pattern; age in seconds of the last dbg-log line matching it (999 if none)
  l=$(grep "$1" "$DBG" 2>/dev/null | tail -n 1)
  [ -z "$l" ] && l=$(zcat "$DBG.0.gz" 2>/dev/null | grep "$1" | tail -n 1)   # the dbg-log rotates often
  [ -z "$l" ] && { echo 999; return; }
  t=$(echo "$l" | cut -c1-19 | tr T " ")
  s=$(date -u -d "$t" +%s 2>/dev/null) || { echo 999; return; }
  echo $(( $(date +%s) - s ))
}
# Reference clock: the [seconds] field of every dbg-log line is the same clock as /proc/uptime.
up_now() { cut -d' ' -f1 /proc/uptime; }
line_up() { # $1 = pattern, $2 = 1 to also search dbg-log.0.gz; prints the [seconds] of the last matching line
  l=$(grep "$1" "$DBG" 2>/dev/null | tail -n 1)   # whole file: a film opening writes ~800 lines in one second
  [ -z "$l" ] && [ "$2" = 1 ] && l=$(zcat "$DBG.0.gz" 2>/dev/null | grep "$1" | tail -n 1)
  [ -n "$l" ] && echo "$l" | sed -n 's/^[^ ]* \[\([0-9.]*\)\].*/\1/p'
}
NATIVE='NOTIFY_INVOKE.*SOURCE_ID":"com.webos.service.\(pqcontroller\|audio\)".*CONTENT":"\(HDR\|Dolby Vision\|HLG\)'
# How LG chains its own toasts (SystemUI/Notification, NotificationView.qml + Services.qml): one toast on
# screen at a time; a toast that arrives while another is showing goes to a queue and, 2000 ms later,
# the one on screen is closed and the queued one comes in (and then stays its full 5000 ms). That is how
# LG itself shows "HDR" and then "Dolby Atmos". So the right moment for ours is right AFTER LG's badge
# has been sent: the system then gives LG's 2 s and slides ours in. Sent BEFORE LG's, ours would be the
# one cut after 2 s. So: wait for LG's badge only when one is coming, and send ours right after it.
wait_native() { # $1 = [seconds] of the event, $2 = how long to wait (s), $3 = how far before the event LG's may be (s)
  k=0
  while [ $k -lt $(($2 * 4)) ]; do
    nat=$(line_up "$NATIVE" 0)
    if [ -n "$nat" ] && awk -v a="$1" -v x="$nat" -v b="$3" 'BEGIN{ exit !(x >= a - b) }'; then usleep 300000; return; fi
    usleep 250000; k=$((k+1))
  done
}
video_is_sdr() { # the last video setDecodeInfo after the event says "none" (no HDR / DV): LG shows no badge
  grep "avc.main setDecodeInfo" "$DBG" 2>/dev/null | grep "contentType\[video\]" | tail -n 1 | grep -q '\\"none\\",\\"nonAdaptive\\"'
}
smart_wait() {
  # Films (apps): a new pipeline (< 20 s ago) gets LG's HDR / Dolby Vision badge unless the video is SDR;
  # an audio track change (< 5 s ago) gets the audio service's "Dolby Vision" badge on DV titles.
  now=$(up_now); p=$(line_up start_pipeline_init 1); t=$(line_up SELECT_TRACK 1)
  set -- $(awk -v n="$now" -v p="${p:-0}" -v t="${t:-0}" 'BEGIN{ if (n-p < 20) print p, 12; else if (n-t < 5) print t, 3; else print 0, 0 }')
  [ "$2" = 0 ] && return
  [ "$2" = 12 ] && video_is_sdr && return
  wait_native "$1" "$2" 0.5
}

# HDMI inputs: no pipeline / track events there; LG's HDR / DV badge for the input comes when the input
# (re)starts, from a few seconds before the audio format change to ~3 s after it.
last_hdmi_line() { grep 'audiooutputd.*setQualityAttribute request.*categoryInfo.*"sourceType":"HDMI"' | tail -n 1; }
hdmi_msg() { # $1 = codec, $2 = immersive
  case "$1" in
    mat_atmos*|matatmos*|mat*) echo "Dolby Atmos" ;;
    eac3*|ec3|ddp) [ -n "$2" ] && [ "$2" != "none" ] && echo "Dolby Atmos" || echo "Dolby Digital Plus" ;;
    ac3) echo "Dolby Digital" ;;
    dts*) echo "DTS Digital Surround" ;;
    *) [ -n "$2" ] && [ "$2" != "none" ] && echo "Dolby Atmos" ;;   # pcm / none: no badge
  esac
}

# Whole current dbg-log (it rotates at ~1 MB): opening a film writes ~800 lines in the same second as the
# audio line, so a short tail (it was 400 lines) lost it before the next poll and no Dolby badge came out.
last_audio_line() { grep "avc.main setDecodeInfo" "$DBG" 2>/dev/null | grep "contentType\[audio\]" | tail -n 1; }
field() { echo "$1" | grep -o "$2[^,}]*" | head -n 1 | sed "s/$2//; s/[^a-zA-Z0-9]//g"; }   # codec / immersive

echo $$ > "$PIDF"
log "started (pid $$)"

# A DTS decision already there at start: only shown if recent (< 10 s).
last=""
if [ -f "$DEC" ]; then
  cur=$(cat "$DEC" 2>/dev/null)
  ts=${cur%% *}
  now=$(date +%s)
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  if [ $((now - ts)) -gt 10 ]; then last="$cur"; fi
fi
# An audio track already playing at start: not shown.
la=$(last_audio_line); last_audio_ts=${la%% *}
lh=$(last_hdmi_line); last_hdmi_ts=${lh%% *}; hdmi_shown=""; hdmi_shown_at=0

while :; do
  # --- DTS ---
  cur=$(cat "$DEC" 2>/dev/null)
  if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
    last="$cur"
    if [ -f "$DIR/disabled" ]; then
      log "disabled: $cur"
    else
      case "$cur" in
        *" passthrough"*) msg="DTS Digital Surround" ;;
        *) msg="DTS Digital Surround (TV)" ;;   # decoded by the TV, not passed through
      esac
      smart_wait
      log "dts [$cur] -> '$msg' : $(toast "$msg" "$ICON")"
    fi
  fi

  # --- Dolby Digital / Dolby Digital Plus / Dolby Atmos ---
  la=$(last_audio_line)
  ats=${la%% *}
  if [ -n "$la" ] && [ "$ats" != "$last_audio_ts" ]; then
    last_audio_ts="$ats"
    codec=$(field "$la" codec); imm=$(field "$la" immersive)
    case "$codec" in
      ac3|eac3|ec3|ddp) dolby=1 ;;
      *) dolby=0 ;;   # (dts_restore_plus' DTS shows up here as "pcm")
    esac
    if [ $dolby = 1 ]; then
      if [ -f "$DIR/disabled" ] || [ -f "$DIR/disabled_dolby" ]; then
        log "dolby disabled: codec=$codec immersive=$imm"
      else
        usleep 500000   # the TV sends two lines per track change (old track, then new, ~20 ms apart): the last one counts
        smart_wait
        la=$(last_audio_line); [ -n "$la" ] && { last_audio_ts=${la%% *}; ats=$last_audio_ts; codec=$(field "$la" codec); imm=$(field "$la" immersive); }
        case "$codec" in
          ac3) dmsg="Dolby Digital" ;;
          eac3|ec3|ddp) dmsg="Dolby Digital Plus" ;;
          *) dmsg="" ;;
        esac
        if [ -n "$dmsg" ] && [ -n "$imm" ] && [ "$imm" != "none" ]; then dmsg="Dolby Atmos"; fi
        if [ -z "$dmsg" ]; then
          log "audio changed to $codec - no Dolby badge"
        elif [ "$dmsg" = "Dolby Atmos" ] && [ "$(line_age 'NOTIFY_INVOKE.*SOURCE_ID":"com.webos.service.audio".*CONTENT":"[^"]*Atmos')" -lt 15 ]; then
          log "atmos: LG already showed an Atmos badge - nothing to do (codec=$codec)"
        else
          log "audio [$ats codec=$codec immersive=$imm] -> '$dmsg' : $(toast "$dmsg" "$DOLBY_ICON")"
        fi
      fi
    fi
  fi
  # --- HDMI inputs ---
  lh=$(last_hdmi_line)
  hts=${lh%% *}
  if [ -n "$lh" ] && [ "$hts" != "$last_hdmi_ts" ]; then
    last_hdmi_ts="$hts"
    sleep 2   # a format change passes through "none"/"pcm" for an instant: wait until it settles
    lh=$(last_hdmi_line); [ -n "$lh" ] && last_hdmi_ts=${lh%% *}
    hcodec=$(field "$lh" codec); himm=$(field "$lh" immersive)
    hin=$(echo "$lh" | sed -n 's/.*"contentType":"\(hdmi[0-9]*\)".*/\1/p')
    hmsg=$(hdmi_msg "$hcodec" "$himm")
    hup=$(echo "$lh" | sed -n 's/^[^ ]* \[\([0-9.]*\)\].*/\1/p')
    now=$(date +%s)
    if [ -z "$hmsg" ]; then
      :   # pcm / none: nothing to show (and it does not reset the last badge)
    elif [ -f "$DIR/disabled" ] || [ -f "$DIR/disabled_hdmi" ]; then
      log "hdmi disabled: $hin codec=$hcodec immersive=$himm"
    elif [ "$hin:$hmsg" = "$hdmi_shown" ] && [ $((now - hdmi_shown_at)) -lt 60 ]; then
      log "hdmi: $hin back to $hmsg within 60 s - not repeated"
    else
      wait_native "${hup:-0}" 3 8
      if [ "$hmsg" = "Dolby Atmos" ] && [ "$(line_age 'NOTIFY_INVOKE.*SOURCE_ID":"com.webos.service.audio".*CONTENT":"[^"]*Atmos')" -lt 15 ]; then
        log "hdmi: LG already showed an Atmos badge - nothing to do ($hin)"
      else
        icon=$DOLBY_ICON; [ "$hmsg" = "DTS Digital Surround" ] && icon=$ICON
        log "hdmi [$hts $hin codec=$hcodec immersive=$himm] -> '$hmsg' : $(toast "$hmsg" "$icon")"
      fi
      hdmi_shown="$hin:$hmsg"; hdmi_shown_at=$(date +%s)
    fi
  fi
  sleep 1
done
