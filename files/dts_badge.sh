#!/bin/sh
# Audio badges in LG's native style (the "light" toast LG itself uses for HDR / Dolby Vision):
#  - DTS: follows the decision dts_restore_plus' dtsdec writes to /run/dtsc1/last-decision.
#  - Dolby Digital / Dolby Digital Plus / Dolby Atmos: follows the audio "setDecodeInfo" lines in the dbg-log.
# Turn all badges off:      touch /var/lib/webosbrew/dts_badge/disabled
#  - HDMI inputs (e.g. a console): follows audiooutputd's "setAudioInputInfo" lines (sourceType HDMI).
# Turn Dolby badges off:    touch /var/lib/webosbrew/dts_badge/disabled_dolby
# Turn HDMI badges off:     touch /var/lib/webosbrew/dts_badge/disabled_hdmi
#  - PCM after bitstream: when an app that plays plain PCM (YouTube) starts right after a bitstream source
#    (Dolby / Atmos passthrough) ended, nudges the digital output (Auto and back, ~0.3 s) so it is not muted.
# Turn that fix off:        touch /var/lib/webosbrew/dts_badge/disabled_pcm_fix
#  - DTS renderer fix: while a DTS passthrough plays, sets LG's PCM renderer "metadata type" to 0 (it scales the
#    samples, which turns the DTS bitstream into noise) and puts the old value back when it ends.
# Turn that fix off:        touch /var/lib/webosbrew/dts_badge/disabled_dts_renderer
DIR=/var/lib/webosbrew/dts_badge
DEC=/run/dtsc1/last-decision
DBG=/tmp/var/log/dbg-log
RUN=/run/dts_badge   # runtime files: a root-only place (/tmp is writable by every app on the TV)
mkdir -p "$RUN" && chmod 700 "$RUN"
LOG=$RUN/dts_badge.log
ICON=$DIR/dts_icon.png
DOLBY_ICON=/usr/share/pqcontroller/images/light_toast_icon_dolby.png   # LG's own icon, already on the TV
PIDF=$RUN/dts_badge.pid

# The dbg-log rotates at ~2 MB (every few minutes while something plays). A line written just before a
# rotation is only in dbg-log.0.gz, so while the current file is still small its predecessor's tail is
# read too (unpacked once per rotation into $PREV). Without this a console change at 04:33:56 was lost:
# the log rotated at 04:33:57.
PREV=$RUN/dbg-log.prev
dbg_cat() {
  if [ "$(wc -c < "$DBG" 2>/dev/null || echo 0)" -lt 800000 ] && [ -f "$DBG.0.gz" ]; then
    k=$(ls -l "$DBG.0.gz" 2>/dev/null)
    if [ "$k" != "$(cat "$PREV.key" 2>/dev/null)" ]; then
      zcat "$DBG.0.gz" 2>/dev/null | tail -n 3000 > "$PREV.tmp" && mv -f "$PREV.tmp" "$PREV"; echo "$k" > "$PREV.key"
    fi
    cat "$PREV" 2>/dev/null
  fi
  cat "$DBG" 2>/dev/null
}

log() { # the log lives in /tmp; past 64 KB only its tail is kept
  [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 65536 ] && { tail -n 200 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }
  echo "$(date -u '+%F %T') $*" >> "$LOG"; }

toast() { # $1 = text, $2 = icon (without the icon file the badge shows text only)
  ic=""; [ -f "$2" ] && ic="\"iconUrl\":\"$2\","
  timeout -t 10 luna-send -n 1 luna://com.webos.notification/createToast \
    "{\"sourceId\":\"com.webos.service.pqcontroller\",\"message\":\"$1\",${ic}\"noaction\":true,\"type\":\"light\"}" </dev/null 2>&1
}

line_age() { # $1 = pattern; age in seconds of the last dbg-log line matching it (999 if none)
  l=$(dbg_cat | grep "$1" | tail -n 1)
  [ -z "$l" ] && l=$(zcat "$DBG.0.gz" 2>/dev/null | grep "$1" | tail -n 1)   # the dbg-log rotates often
  [ -z "$l" ] && { echo 999; return; }
  t=$(echo "$l" | cut -c1-19 | tr T " ")
  s=$(date -u -d "$t" +%s 2>/dev/null) || { echo 999; return; }
  echo $(( $(date +%s) - s ))
}
# Reference clock: the [seconds] field of every dbg-log line is the same clock as /proc/uptime.
up_now() { cut -d' ' -f1 /proc/uptime; }
line_up() { # $1 = pattern, $2 = 1 to also search dbg-log.0.gz; prints the [seconds] of the last matching line
  l=$(dbg_cat | grep "$1" | tail -n 1)   # whole file: a film opening writes ~800 lines in one second
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
  k=0; found_nat=""
  while [ $k -lt $(($2 * 4)) ]; do
    nat=$(line_up "$NATIVE" 0)
    if [ -n "$nat" ] && awk -v a="$1" -v x="$nat" -v b="$3" 'BEGIN{ exit !(x >= a - b) }'; then found_nat=$nat; usleep 300000; return; fi
    usleep 250000; k=$((k+1))
  done
}
video_is_sdr() { # the last video setDecodeInfo after the event says "none" (no HDR / DV): LG shows no badge
  dbg_cat | grep "avc.main setDecodeInfo" | grep "contentType\[video\]" | tail -n 1 | grep -q '\\"none\\",\\"nonAdaptive\\"'
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
# Audio input lines: read from audiod ("Call setQualityAttribute API with payload ... setAudioInputInfo"), not
# from audiooutputd: the TV's log daemon stops audiooutputd's messages when it logs too much
# ("NL_LOG_BLOCKED audiooutputd", seen 26/11 22:24) and from then on its lines (and setEArcOutputType) are gone.
SRC='Call setQualityAttribute API.*setAudioInputInfo'
last_hdmi_line() { dbg_cat | grep "$SRC" | grep '"sourceType":"HDMI"' | tail -n 1; }
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
# LG's own video badge (HDR / Dolby Vision / HLG) from pqcontroller: on an HDMI input it comes back every
# time the source re-sends its video signal (console restart, game start, TV back from standby), even
# when the audio format did not change, so no new audio line arrives. LG then shows only "HDR".
HDR_TOAST='NOTIFY_INVOKE.*SOURCE_ID":"com.webos.service.pqcontroller".*CONTENT":"\(HDR\|Dolby Vision\|HLG\)'
up_of() { echo "$1" | sed -n 's/^[^ ]* \[\([0-9.]*\)\].*/\1/p'; }
newer() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ exit !(a > b) }'; }   # $1 > $2 (uptime seconds)
# LG's own "Dolby Atmos" (audio service; seen on HDMI after the eARC re-sync) came AFTER [seconds] $1:
# then it is already on screen / queued behind that HDR and ours would only repeat it.
lg_atmos_after() { a=$(line_up 'NOTIFY_INVOKE.*SOURCE_ID":"com.webos.service.audio".*CONTENT":"[^"]*Atmos' 0); [ -n "$a" ] && newer "$a" "$1"; }

# Per-track Atmos flag of the audio track this pipeline plays now: last SELECT_TRACK (audio) of the
# pipeline (index 0 if none), then the last handleAudioTrackInfoEvent of that track that carries a flag.
track_immersive() { # $1 = the setDecodeInfo line
  uid=$(echo "$1" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p'); [ -z "$uid" ] && return
  idx=$(dbg_cat | grep "SELECT_TRACK" | grep "$uid" | grep 'audio' | tail -n 1 | sed -n 's/.*index[^0-9]*\([0-9]*\).*/\1/p')
  dbg_cat | grep "handleAudioTrackInfoEvent" | grep "$uid" | grep "trackNo\[${idx:-0}\]" \
    | sed -n 's/.* \([A-Za-z][A-Za-z]*\)\]"}.*/\1/p' | tail -n 1
}

# --- PCM after bitstream ---
# Seen on 26/11: after the PS5 (Dolby Atmos/MAT, eARC "codec type 7") or a Stremio E-AC3 track ("codec
# type 5") the TV left the eARC output in bitstream (setEArcOutputType ... mixer value is 0) when that
# source ended; YouTube then played PCM (Chromium, ALSA: "PcmPrepare") with no sound, now and then. Toggling
# eArcSupport off/on brought the sound back but moved it to the TV speakers for ~4 s while the link came back.
# Switching "Digital Sound Output" to Auto and back to Pass Through for ~0.3 s (the TV re-applies the eARC
# output with the mixer on: "codec type: 7 ... mixer value is 1") keeps the link up and nobody notices it.
digital_nudge() {
  cur=$(timeout -t 10 luna-send -n 1 luna://com.webos.settingsservice/getSystemSettings '{"category":"sound","keys":["soundOutputDigital"]}' </dev/null 2>/dev/null | sed -n 's/.*"soundOutputDigital" *: *"\([^"]*\)".*/\1/p')
  [ "$cur" = "passThrough" ] || { echo "digital output is '$cur', not passThrough - left alone"; return; }
  timeout -t 10 luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings '{"category":"sound","settings":{"soundOutputDigital":"auto"}}' </dev/null >/dev/null 2>&1
  usleep 300000
  timeout -t 10 luna-send -n 1 luna://com.webos.settingsservice/setSystemSettings '{"category":"sound","settings":{"soundOutputDigital":"passThrough"}}' </dev/null 2>&1
}
src_line() { dbg_cat | grep "$SRC" | grep -v '"codec":"none"' | tail -n 1; }   # last audio source that carried a format

# --- DTS renderer fix ---
# Root cause of the DTS noise (found 26/11; same as combor/webos-dts-decoder and dts_restore_plus issue #12):
# every app's PCM goes through LG's MS12 PCM renderer on its way to eARC, and while the renderer's
# "metadata type" is above 1 it scales the samples (by 63/64), which turns dts_restore_plus' IEC 61937 DTS
# into noise. Measured on the C1: Dolby Atmos/MAT from the PS5 leaves it at 3 (an AC3 track puts it back
# to 0, which is why switching to AC3 and back "fixed" it); with 3 the DTS hissed, and writing 0 cleaned
# it at once. So: while our DTS passthrough plays, metadata type 0; afterwards, the old value back.
REN_STATUS=/proc/aaudio/module/PCMREN_P0/status
REN_SET=0x64040004
ren_c=""; ren_uid=""; ren_saved=""
ren_type() { sed -n 's/.*Param *: *metadata type *: *\([0-9]*\).*/\1/p' "$REN_STATUS" 2>/dev/null | head -n 1; }
ren_cmd() { # the renderer's DSP instance command file (its prop carries the module id of the status file)
  id=$(sed -n 's/.*](\([0-9]*\)).*/\1/p' "$REN_STATUS" 2>/dev/null | head -n 1); [ -z "$id" ] && return
  [ -n "$ren_c" ] && timeout -t 2 grep -qx "id=(int)$id" "${ren_c%/cmd}/prop" 2>/dev/null && { echo "$ren_c"; return; }
  for d in /proc/aaudio/instances/*; do   # some instances' prop never returns: always with a timeout
    timeout -t 2 grep -qx "id=(int)$id" "$d/prop" 2>/dev/null && { echo "$d/cmd"; return; }
  done
}
ren_set() { # $1 = metadata type; true when the renderer took it
  c=$(ren_cmd); [ -n "$c" ] || return 1; ren_c=$c
  echo "$REN_SET $1" > "$c" 2>/dev/null || return 1
  i=0; while [ $i -lt 10 ]; do [ "$(ren_type)" = "$1" ] && return 0; usleep 20000; i=$((i+1)); done; return 1
}
# The noise lasts until the value is 0, and the main loop can take seconds per pass (it greps the dbg-log),
# so a light child process watches only dts_restore_plus' decision file, every 0.2 s, and does the write.
# It leaves the old value in $RUN/renderer-metadata-type; the main loop ties it to the film and puts it back.
ren_fast() {
  lm=$(cat "$DEC" 2>/dev/null)
  while :; do
    m=$(cat "$DEC" 2>/dev/null)
    if [ "$m" != "$lm" ]; then
      lm=$m
      case "$m" in *" passthrough"*)
        t=$(ren_type)
        case "$t" in ''|0|1) ;; *)
          if [ ! -f "$DIR/disabled_dts_renderer" ] && ren_set 0; then
            [ -f "$RUN/renderer-metadata-type" ] || echo "$t" > "$RUN/renderer-metadata-type"
            log "dts: PCM renderer metadata type $t -> 0 at the DTS start (it turns the DTS into noise)"
          fi ;;
        esac ;;
      esac
    fi
    usleep 200000
  done
}
ren_fix() { # $1 = the DTS setDecodeInfo line; at a DTS passthrough start (main loop)
  [ -f "$DIR/disabled_dts_renderer" ] && return
  uid=$(echo "$1" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')
  if [ -z "$ren_uid" ] && [ -f "$RUN/renderer-metadata-type" ]; then   # the fast watcher already did it
    ren_uid=$uid; ren_saved=$(cat "$RUN/renderer-metadata-type"); return
  fi
  t=$(ren_type)
  case "$t" in ''|0|1) [ -n "$ren_uid" ] && ren_uid=$uid; return ;; esac   # already safe
  if ren_set 0; then
    [ -z "$ren_saved" ] && ren_saved=$t; ren_uid=$uid; echo "$ren_saved" > "$RUN/renderer-metadata-type"
    log "dts: PCM renderer metadata type $t -> 0 (would turn the DTS into noise)"
  else
    log "dts: PCM renderer metadata type is $t and could not be set to 0"
  fi
}
play_state() { dbg_cat | grep 'getMediaInfo' | grep "\"mediaId\":\"$1\"" | tail -n 1 | sed -n 's/.*"mediaId":"'"$1"'","type":"media","playState":"\([a-z]*\)".*/\1/p'; }
ren_restore_check() { # the DTS film ended, or something else plays: put the old value back
  [ -z "$ren_uid" ] && return
  st=$(play_state "$ren_uid"); src=$(src_line)
  if [ "$st" = "unloaded" ] || { [ -n "$src" ] && ! echo "$src" | grep -q "$ren_uid"; }; then
    if [ "$(ren_type)" = 0 ] && ren_set "$ren_saved"; then log "dts: DTS ended - PCM renderer metadata type 0 -> $ren_saved"
    else log "dts: DTS ended - PCM renderer metadata type left as $(ren_type)"; fi
    ren_uid=""; ren_saved=""; rm -f "$RUN/renderer-metadata-type"
  fi
}

last_audio_line() { dbg_cat | grep "avc.main setDecodeInfo" | grep "contentType\[audio\]" | tail -n 1; }
field() { echo "$1" | grep -o "$2[^,}]*" | head -n 1 | sed "s/$2//; s/[^a-zA-Z0-9]//g"; }   # codec / immersive

# Only one watcher: stop any other copy (an older one left by a reinstall would double every badge).
for p in /proc/[0-9]*; do
  q=${p#/proc/}; [ "$q" = "$$" ] && continue
  case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in
    "/bin/sh /var/lib/webosbrew/dts_badge/dts_badge.sh"*) kill "$q" 2>/dev/null ;;
  esac
done
echo $$ > "$PIDF"
log "started (pid $$)"
# A value saved by a previous run (restart or reinstall): if its DTS film still plays, take it over (the
# main loop puts the value back when the film ends); if not, put it back now.
if [ -f "$RUN/renderer-metadata-type" ]; then
  v=$(cat "$RUN/renderer-metadata-type"); src=$(src_line)
  u=$(echo "$src" | sed -n 's/.*"pipelineId":"\([^"]*\)".*/\1/p')
  if [ "$(field "$src" codec)" = "pcm" ] && [ -n "$u" ] && [ "$(play_state "$u")" != "unloaded" ] && [ -n "$(play_state "$u")" ]; then
    ren_uid=$u; ren_saved=$v; log "dts: a DTS film is still playing - keeping the PCM renderer at 0 (old value $v)"
  else
    rm -f "$RUN/renderer-metadata-type"
    [ "$(ren_type)" = 0 ] && [ -n "$v" ] && ren_set "$v" && log "dts: PCM renderer metadata type 0 -> $v (left by the previous run)"
  fi
fi

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
# What the HDMI input is playing now ("hdmi4:Dolby Atmos"; empty = no badge / an app is playing)
hdmi_state=""; hdmi_state_up=0; our_up=0
if [ -n "$lh" ] && newer "$(up_of "$lh")" "$(up_of "$la")"; then
  hdmi_state="$(echo "$lh" | sed -n 's/.*"contentType":"\(hdmi[0-9]*\)".*/\1/p'):$(hdmi_msg "$(field "$lh" codec)" "$(field "$lh" immersive)")"; hdmi_state_up=$(up_of "$lh")
fi
last_nat=$(line_up "$HDR_TOAST" 0)
last_pcm=$(line_up 'alsa-wrapper.*PcmPrepare' 0); pcm_fixed_for=""
# Right after a boot this watcher starts ~45 s in (webosbrew runs init.d late), but a console on HDMI
# comes up at ~25 s with LG's HDR badge, before we exist. Show that input's badge once now, late but there.
hin=${hdmi_state%%:*}; hmsg=${hdmi_state#*:}
if [ -n "$hmsg" ] && awk -v u="$(up_now)" -v h="$hdmi_state_up" 'BEGIN{ exit !(u < 300 && u - h < 120) }' \
   && ! [ -f "$DIR/disabled" ] && ! [ -f "$DIR/disabled_hdmi" ] \
   && ! { [ "$hmsg" = "Dolby Atmos" ] && lg_atmos_after "${last_nat:-$hdmi_state_up}"; }; then
  icon=$DOLBY_ICON; [ "$hmsg" = "DTS Digital Surround" ] && icon=$ICON
  log "hdmi [$hin at boot, before this watcher started] -> '$hmsg' : $(toast "$hmsg" "$icon")"
  hdmi_shown="$hin:$hmsg"; hdmi_shown_at=$(date +%s); our_up=$(up_now)
fi
ren_c=$(ren_cmd)   # found once here (it can take a while), inherited by the fast watcher
ren_fast &

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
      case "$cur" in *" passthrough"*)   # renderer first (the noise lasts until then), badge after
        dl=$(last_audio_line); [ "$(field "$dl" codec)" = "pcm" ] && ren_fix "$dl" ;;
      esac
      smart_wait
      log "dts [$cur] -> '$msg' : $(toast "$msg" "$ICON")"
    fi
  fi

  # --- Dolby Digital / Dolby Digital Plus / Dolby Atmos ---
  la=$(last_audio_line)
  ats=${la%% *}
  if [ -n "$la" ] && [ "$ats" != "$last_audio_ts" ]; then
    last_audio_ts="$ats"; hdmi_state=""   # an app is playing now
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
        # The "immersive" of the setDecodeInfo sent on a track change is the PREVIOUS track's (an AC3 track
        # picked after an Atmos one showed "ac3 / atmos"). AC3 never carries Atmos; for E-AC3 the per-track
        # info (handleAudioTrackInfoEvent ... ATMOS / none) of the selected track is the reliable source.
        if [ "$dmsg" = "Dolby Digital Plus" ]; then
          ti=$(track_immersive "$la")
          case "$ti" in
            ATMOS|atmos) dmsg="Dolby Atmos" ;;
            none) : ;;
            *) [ -n "$imm" ] && [ "$imm" != "none" ] && dmsg="Dolby Atmos" ;;   # track not described yet
          esac
          imm="$imm/track:${ti:-?}"
        fi
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
    hdmi_state="$hin:$hmsg"; hdmi_state_up=$(up_of "$lh")
    hup=$(echo "$lh" | sed -n 's/^[^ ]* \[\([0-9.]*\)\].*/\1/p')
    now=$(date +%s)
    if [ -z "$hmsg" ]; then
      :   # pcm / none: nothing to show (and it does not reset the last badge)
    elif [ -f "$DIR/disabled" ] || [ -f "$DIR/disabled_hdmi" ]; then
      log "hdmi disabled: $hin codec=$hcodec immersive=$himm"
    else
      wait_native "${hup:-0}" 3 8
      ref=${found_nat:-$(awk -v h="${hup:-0}" 'BEGIN{ print h - 8 }')}
      if [ -z "$found_nat" ] && [ "$hin:$hmsg" = "$hdmi_shown" ] && [ $((now - hdmi_shown_at)) -lt 60 ]; then
        log "hdmi: $hin back to $hmsg within 60 s, no LG badge with it - not repeated"   # format flapping
      elif [ "$hmsg" = "Dolby Atmos" ] && lg_atmos_after "$ref"; then
        log "hdmi: LG showed its own Atmos badge after its HDR - nothing to do ($hin)"
      else
        icon=$DOLBY_ICON; [ "$hmsg" = "DTS Digital Surround" ] && icon=$ICON
        log "hdmi [$hts $hin codec=$hcodec immersive=$himm] -> '$hmsg' : $(toast "$hmsg" "$icon")"
        hdmi_shown="$hin:$hmsg"; hdmi_shown_at=$(date +%s); our_up=$(up_now)
      fi
    fi
  fi
  # --- HDMI: LG showed its HDR badge again but the audio did not change ---
  nat=$(line_up "$HDR_TOAST" 0)
  if [ -n "$nat" ] && [ "$nat" != "$last_nat" ]; then
    last_nat="$nat"
    usleep 1500000   # let an audio change that comes with it land first: then the block above handles it
    lh=$(last_hdmi_line); p=$(line_up start_pipeline_init 0)
    if [ -n "$lh" ] && [ "${lh%% *}" != "$last_hdmi_ts" ]; then
      :   # the audio changed too: the HDMI block takes it on the next pass
    elif [ -n "$p" ] && newer "$p" "$hdmi_state_up"; then
      :   # an app started a video after the last HDMI audio line: not an HDMI badge
    else
      hin=${hdmi_state%%:*}; hmsg=${hdmi_state#*:}
      if [ -z "$hmsg" ]; then
        :   # pcm / no audio badge for this input, or an app is playing
      elif [ -f "$DIR/disabled" ] || [ -f "$DIR/disabled_hdmi" ]; then
        log "hdmi disabled: $hin LG badge again ($hmsg)"
      elif ! newer "$nat" "$(awk -v u="$our_up" 'BEGIN{ print u + 10 }')"; then
        :   # ours went out with this LG badge already
      elif [ "$hmsg" = "Dolby Atmos" ] && lg_atmos_after "$nat"; then
        log "hdmi: LG showed its own Atmos badge after its HDR - nothing to do ($hin)"
      else
        icon=$DOLBY_ICON; [ "$hmsg" = "DTS Digital Surround" ] && icon=$ICON
        log "hdmi [$hin, LG badge again at $nat, audio unchanged] -> '$hmsg' : $(toast "$hmsg" "$icon")"
        hdmi_shown="$hin:$hmsg"; hdmi_shown_at=$(date +%s); our_up=$(up_now)
      fi
    fi
  fi
  ren_restore_check
  # --- PCM after bitstream (see digital_nudge) ---
  pcm=$(line_up 'alsa-wrapper.*PcmPrepare' 0)
  if [ -n "$pcm" ] && [ "$pcm" != "$last_pcm" ]; then
    last_pcm="$pcm"
    et=$(src_line); etu=$(up_of "$et"); ec=$(field "$et" codec)
    dis=$(line_up 'UMI/disconnect' 0)
    case "$ec" in pcm|unknown|"") bits=0 ;; *) bits=1 ;; esac   # ac3, eac3, mat_atmos, dts...: bitstream
    if [ $bits = 1 ] && [ -n "$dis" ] && newer "$dis" "$etu" && newer "$pcm" "$dis" && [ "$dis" != "$pcm_fixed_for" ]; then
      pcm_fixed_for="$dis"
      if [ -f "$DIR/disabled_pcm_fix" ]; then
        log "pcm: PCM app after bitstream (last source: $ec) - fix disabled"
      else
        log "pcm: PCM app after bitstream (last source: $ec) -> digital output Auto/Pass Through : $(digital_nudge)"
      fi
    fi
  fi
  sleep 1
done
