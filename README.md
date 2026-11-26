# DTS Free LG TV C1 - WebOS Rooted + Visual Mods

Audio badges (DTS / Dolby) in LG's native style, a post-boot eARC fix and an earlier DTS hook for rooted LG webOS TVs.

[Português](README.pt-BR.md)

An add-on for [dts_restore_plus](https://github.com/josippapez/dts_restore_plus) by josippapez, which brings
DTS (with ARC/eARC passthrough) back to LG TVs that lost it. This repository does **not** include or modify
its code: it is a prerequisite.

Tested on an LG OLED C1 (webOS 6, GStreamer 1.16) with a soundbar on eARC.

## What it does

- **Audio badges in LG's native style.** Uses the same top-right toast the TV shows for "HDR" and
  "Dolby Vision", with the same animation and duration (it is the system toast itself, type `light`):
  - "DTS Digital Surround" when DTS goes straight to the receiver ("DTS Digital Surround (TV)" if the TV decodes it);
  - "Dolby Digital" (AC3), "Dolby Digital Plus" (E-AC3) and "Dolby Atmos" (E-AC3 with Atmos).
  The badge always comes after LG's HDR/Dolby Vision badge, never over it, through the system's own toast queue.
  It also works for HDMI inputs (e.g. a console sending Dolby Atmos in passthrough, which LG itself does not badge),
  including when LG shows HDR again with the audio unchanged (console restart, TV back from standby).
  Right after power-on the HDMI badge comes ~20 s after HDR: webosbrew's scripts start after the console is up.
- **No DTS noise after Dolby Atmos.** LG's PCM renderer (every app's sound goes through it on the way to eARC)
  scales the samples while its "metadata type" is above 1, which turns the DTS bitstream into loud noise.
  Dolby Atmos/MAT (e.g. a PS5) leaves it at 3. While a DTS passthrough plays, the script sets it to 0 (a light
  watcher does it within ~0.2 s of the DTS start) and puts the old value back when the film ends. Same finding as
  [combor/webos-dts-decoder](https://github.com/combor/webos-dts-decoder) and
  [dts_restore_plus #12](https://github.com/josippapez/dts_restore_plus/issues/12).
- **YouTube sound after Dolby/Atmos.** When an app that plays plain PCM (YouTube) opens right after a bitstream
  source (Dolby/Atmos passthrough, from an app or HDMI), eARC can stay in bitstream and the app is sometimes
  silent. The script notices and switches "Digital Sound Output" to Auto and back to Pass Through (~0.3 s, the
  eARC link stays up).
- **Post-boot eARC fix.** On some sets, after a cold boot the eARC link comes up without finishing the sync
  with the soundbar, and DTS passthrough turns into loud noise. Toggling "eARC Support" off and on fixes it;
  the script does that once, about a minute after boot (sound drops for ~3 s), and checks the result in the log.
- **Earlier DTS at boot.** Runs dts_restore_plus' init script at the start of webosbrew's startup queue
  (~10 s earlier), so apps are less likely to open a film before DTS is active.

## Requirements

- A rooted LG TV with [Homebrew Channel / webosbrew](https://www.webosbrew.org/) (`/var/lib/webosbrew/init.d`).
- [dts_restore_plus](https://github.com/josippapez/dts_restore_plus) installed (`install.sh --passthrough` for passthrough).
- Root SSH access (not telnet).

## Install

Copy this folder to the TV (e.g. `scp -r`), ssh in, and run:

```sh
sh install.sh
```

To remove: `sh uninstall.sh` (leaves dts_restore_plus alone). If you uninstall dts_restore_plus, run this
`uninstall.sh` too, so `00-dts-early` goes away.

## DTS icon

No brand artwork ships here. The Dolby badge uses the icon already on the TV
(`/usr/share/pqcontroller/images/light_toast_icon_dolby.png`). For DTS, build one from an official "dts"
logo SVG you have (remove the ® from the SVG first; at this size it becomes a dot):

```sh
pip install cairosvg pillow
python3 tools/make_dts_icon.py dts_logo.svg dts_icon.png
```

Put `dts_icon.png` next to `install.sh` before installing. Without it the DTS badge shows text only.

## Turning parts off

| What | How |
|---|---|
| All badges | `touch /var/lib/webosbrew/dts_badge/disabled` |
| Dolby badges only | `touch /var/lib/webosbrew/dts_badge/disabled_dolby` |
| HDMI input badges only | `touch /var/lib/webosbrew/dts_badge/disabled_hdmi` |
| Post-boot eARC fix | `touch /var/lib/webosbrew/dts_badge/disabled_earc_fix` |
| YouTube sound fix | `touch /var/lib/webosbrew/dts_badge/disabled_pcm_fix` |
| DTS noise fix (renderer) | `touch /var/lib/webosbrew/dts_badge/disabled_dts_renderer` |

Logs: `/run/dts_badge/dts_badge.log`, `/run/dts_badge/earc_fix.log` (root-only folder; cleared at reboot).

## How it works

- LG's native badge is a `luna://com.webos.notification/createToast` with `"type":"light"` (what
  `pqcontroller` uses for HDR/Dolby Vision). The script uses the same toast with its own icon and text.
- DTS: reads the decision dts_restore_plus' dtsdec writes to `/run/dtsc1/last-decision`.
- Dolby: reads the audio `setDecodeInfo` lines in `/tmp/var/log/dbg-log` (`codec`). AC3 is always "Dolby Digital";
  for E-AC3, Atmos comes from the selected track's info (`handleAudioTrackInfoEvent … ATMOS/none`), because on a
  track change the `immersive` in `setDecodeInfo` is still the previous track's. The whole log is read, plus the
  tail of the previous one right after each rotation.
- HDMI: follows `audiooutputd`'s `setAudioInputInfo` lines and `pqcontroller`'s HDR/Dolby Vision toasts.
- YouTube sound: when Chromium opens audio (`PcmPrepare`) right after a bitstream source (AC3, E-AC3, MAT) ended,
  sets `soundOutputDigital` to `auto` and back to `passThrough`.
- DTS renderer: reads `/proc/aaudio/module/PCMREN_P0/status` ("Param : metadata type") and writes
  `0x64040004 <type>` to the command file of the renderer's DSP instance under `/proc/aaudio/instances`.
- Audio inputs are read from `audiod`'s `setQualityAttribute` calls: the TV's log daemon can block
  `audiooutputd`'s messages when it logs too much (`NL_LOG_BLOCKED`).
- eARC: toggles `eArcSupport` through `com.webos.settingsservice/setSystemSettings` and checks for
  `audioDeviceType[sound_mode_sync]` in `arccontroller` messages.
- Every startup hook always exits 0, so webosbrew's failsafe is never tripped.

## Caveats

- An LG firmware update may remove root; keep Homebrew Channel's update blocking on.
- If you open a DTS film in the first seconds after power-on, the app may get "codec not supported" before
  dts_restore_plus is active. Just open it again.
- Unofficial; not affiliated with LG, Dolby or DTS. Use at your own risk.

## Credits

- [dts_restore_plus](https://github.com/josippapez/dts_restore_plus) by josippapez, based on Pete Batard's work
  ([RootMyTV #72](https://github.com/RootMyTV/RootMyTV.github.io/issues/72)). Its own licenses (LGPL-2.1 / GPL-2.0).
- [webosbrew](https://www.webosbrew.org/) / Homebrew Channel.
