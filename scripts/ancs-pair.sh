#!/bin/sh
# Open a short, deliberate pairing window for the iPhone (ANCS).
#
# The advertising service unregisters ancs4linux's pairing agent at boot on
# purpose: that agent auto-accepts any bond and only *tells* you the passkey
# afterwards, so leaving it registered while advertising runs permanently would
# let anything in range pair itself. This turns it on for as long as you need
# to tap the laptop on the phone, then turns it back off.
#
# Usage: ancs-pair.sh [seconds]   (default 120)
set -eu

CTL=/mnt/shared/projects/ancs4linux/.venv/bin/ancs4linux-ctl
WINDOW="${1:-120}"

[ -x "$CTL" ] || { echo "no ancs4linux-ctl at $CTL" >&2; exit 1; }

cleanup() {
    "$CTL" disable-pairing 2>/dev/null || true
    notify-send "ANCS pairing" "Pairing window closed." 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$CTL" enable-pairing
notify-send "ANCS pairing" \
    "Open Settings > Bluetooth on the iPhone and tap this laptop. Window closes in ${WINDOW}s." \
    2>/dev/null || true
echo "Pairing open for ${WINDOW}s. Accept on the phone."
sleep "$WINDOW"
