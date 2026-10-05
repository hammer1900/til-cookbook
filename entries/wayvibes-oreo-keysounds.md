# Native Global Keyboard Sounds on Linux: Wayvibes + EG Oreo

*Replace RAM-hungry Electron keysound apps with a ~5 MB native binary and the bundle-ready MechvibesDX OREO pack.*

## Problem

I wanted the **OREO** keysound that ships with Mechvibes, but Mechvibes is
Electron-based and sat at hundreds of MB of idle RAM just to play key clicks.
I tried Rustyvibes and IBM's keysound tool too; neither fit. I assumed switching
to a lighter engine meant extracting the OREO pack and hand-converting its
config.

It doesn't. Wayvibes reads the Mechvibes soundpack format **natively**, and its
repo already ships `eg-oreo`, so there is no extraction or conversion step at all.

## Solution

[Wayvibes](https://github.com/sahaj-b/wayvibes) is a small C++ CLI that captures
keypresses globally with `libevdev` and plays audio with `miniaudio`. It supports
both Mechvibes pack flavors, auto-detected:

- **V1 (classic):** `defines` maps key codes to one wav file per key.
- **V2 (MechvibesDX):** `definitions` maps W3C key names (`KeyA`, `Space`, ...) to
  `[start_ms, end_ms]` slices inside a single `audio_file`; plays on press *and* release.

`eg-oreo` is a V2 pack (one `oreo.wav` plus a sliced `config.json`), already in
`soundpacks/`. Point Wayvibes at it and run it as a **systemd user service** so it
starts with the graphical session, with the output sink pinned and its volume
controlled independently of the system mixer.

## Code

Clone and build, then add yourself to the `input` group and re-login:

```bash
git clone https://github.com/sahaj-b/wayvibes ~/wayvibes
cd ~/wayvibes && make
sudo usermod -aG input "$USER"   # log out / back in for this to take effect
```

Install the service and volume helper (auto-detects your default sink):

```bash
./scripts/wayvibes-oreo-keysounds/install.sh
```

> Full files: [`scripts/wayvibes-oreo-keysounds/`](../scripts/wayvibes-oreo-keysounds/)

The unit that gets installed (`PULSE_SINK` is filled in by the installer):

```ini
[Unit]
Description=wayvibes keyboard sound (EG Oreo)
After=graphical-session.target pipewire-pulse.service
Wants=pipewire-pulse.service
PartOf=graphical-session.target

[Service]
Environment=PULSE_SINK=alsa_output.pci-0000_00_1b.0.analog-stereo
ExecStart=%h/.local/bin/wayvibes %h/wayvibes/soundpacks/eg-oreo -v 1.0
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

Independent keysound volume (`wayvibes-volume up|down|mute|set|status`):

```bash
id=$(wpctl status | sed -n '/Streams:/,/Video/p' | awk '/wayvibes/{gsub(/[^0-9]/,"",$1); print $1; exit}')
wpctl set-volume "$id" "5%+"
```

## Notes

- **Memory:** Wayvibes measured at **~5.6 MB resident** (peak 17.8 MB) in this
  setup, versus hundreds of MB for Electron Mechvibes.
- **V2 semantics:** `timing[0]` fires on key press, `timing[1]` on release; keys
  with a single timing only play on press.
- **Sink pinning:** `PULSE_SINK` targets one output (e.g. the analog jack) so
  keysounds don't follow the default device. Override it with
  `WAYVIBES_SINK=... install.sh` if you want a specific output.
- **Device pin:** the selection is stored in `~/.config/wayvibes/input_device`
  (here `/dev/input/event3`, "AT Translated Set 2 keyboard"); reset it with
  `wayvibes --device`.
- **Works on X11 and Wayland:** capture happens at the evdev layer, not through a
  display-server API, so the display protocol is irrelevant. (This machine is X11
  and it works fine.)
- **Ogg packs:** `miniaudio` can't decode all ogg files; Wayvibes offers a one-time
  `ffmpeg` → wav conversion on first launch, or do it manually and update
  `config.json`.
- **Dependencies:** `libevdev` and `nlohmann-json` to build; `wpctl`
  (PipeWire) or `pactl` (PulseAudio) for the volume helper.
