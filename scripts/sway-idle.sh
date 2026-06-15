#!/bin/sh
# Idle/lock daemon for sway. Factored into its own script so the caffeine
# toggle (caffeine-toggle.sh) can cleanly stop and restart it.

LOCK='/home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000'

exec swayidle -w \
    timeout 300 "$LOCK" \
    timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' \
    after-resume 'swaymsg "output * dpms on"' \
    before-sleep "$LOCK" \
    lock "$LOCK"
