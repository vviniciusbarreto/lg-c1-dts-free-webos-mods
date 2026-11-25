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
  The badge always comes after LG's HDR/Dolby Vision badge, never over it.
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
| eARC fix | `touch /var/lib/webosbrew/dts_badge/disabled_earc_fix` |

Logs: `/tmp/dts_badge.log`, `/tmp/earc_fix.log`.

## How it works

- LG's native badge is a `luna://com.webos.notification/createToast` with `"type":"light"` (what
  `pqcontroller` uses for HDR/Dolby Vision). The script uses the same toast with its own icon and text.
- DTS: reads the decision dts_restore_plus' dtsdec writes to `/run/dtsc1/last-decision`.
- Dolby: reads the audio `setDecodeInfo` lines in `/tmp/var/log/dbg-log` (`codec`, `immersive`).
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
