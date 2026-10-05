#!/usr/bin/env bash
# Install Wayvibes + EG Oreo as a systemd user service on Linux.
#
# Usage:
#   ./install.sh
#   WAYVIBES_SINK=alsa_output.pci-0000_00_1b.0.analog-stereo ./install.sh
#   WAYVIBES_VOLUME=3 ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_TEMPLATE="$SCRIPT_DIR/wayvibes.service"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_DEST="$UNIT_DIR/wayvibes.service"
BIN_DIR="$HOME/.local/bin"

red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[0;33m%s\033[0m\n' "$*"; }

die() { red "error: $*" >&2; exit 1; }

[ -f "$UNIT_TEMPLATE" ] || die "missing service template: $UNIT_TEMPLATE"

# --- Resolve the wayvibes binary -------------------------------------------
if command -v wayvibes >/dev/null 2>&1; then
  WAYVIBES_BIN="$(command -v wayvibes)"
elif [ -x "$HOME/wayvibes/wayvibes" ]; then
  WAYVIBES_BIN="$HOME/wayvibes/wayvibes"
else
  die "wayvibes not found. Build it first: git clone https://github.com/sahaj-b/wayvibes ~/wayvibes && cd ~/wayvibes && make"
fi

# --- Resolve the soundpack --------------------------------------------------
SOUNDPACK="${WAYVIBES_SOUNDPACK:-$HOME/wayvibes/soundpacks/eg-oreo}"
[ -f "$SOUNDPACK/config.json" ] \
  || die "soundpack not found at $SOUNDPACK (set WAYVIBES_SOUNDPACK=/path/to/pack)"

# --- Resolve the output sink ------------------------------------------------
if [ -n "${WAYVIBES_SINK:-}" ]; then
  SINK="$WAYVIBES_SINK"
elif command -v pactl >/dev/null 2>&1 && SINK="$(pactl get-default-sink 2>/dev/null)" && [ -n "$SINK" ]; then
  :
else
  SINK="alsa_output.pci-0000_00_1b.0.analog-stereo"
  yellow "could not detect a default sink; falling back to $SINK"
fi

VOLUME="${WAYVIBES_VOLUME:-1.0}"

# --- input group check ------------------------------------------------------
if ! id -nG "$USER" 2>/dev/null | grep -qw input; then
  yellow "warning: '$USER' is not in the 'input' group."
  yellow "  run: sudo usermod -aG input $USER   (then log out / back in)"
fi

# --- Install the unit -------------------------------------------------------
mkdir -p "$UNIT_DIR" "$BIN_DIR"
sed \
  -e "s|__PULSE_SINK__|$SINK|g" \
  -e "s|__WAYVIBES_BIN__|$WAYVIBES_BIN|g" \
  -e "s|__SOUNDPACK__|$SOUNDPACK|g" \
  -e "s|__VOLUME__|$VOLUME|g" \
  "$UNIT_TEMPLATE" >"$UNIT_DEST"

# --- Install the volume helper ---------------------------------------------
install -m 0755 "$SCRIPT_DIR/wayvibes-volume" "$BIN_DIR/wayvibes-volume"

# --- Enable and start -------------------------------------------------------
systemctl --user daemon-reload
systemctl --user enable --now wayvibes.service

green "installed:"
echo "  unit      -> $UNIT_DEST"
echo "  helper    -> $BIN_DIR/wayvibes-volume"
echo "  soundpack -> $SOUNDPACK"
echo "  sink      -> $SINK"
echo
systemctl --user --no-pager status wayvibes.service || true
