#!/bin/sh
# Idle/lock daemon for sway. Factored into its own script so the caffeine
# toggle (caffeine-toggle.sh) can cleanly stop and restart it.

# Lock command. Text colors are set transparent (00000000) so no status words
# ("Verifying", "Wrong", "Cleared", caps-lock) are ever drawn on the locker.
LOCK='/home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000 --text-color 00000000 --text-ver-color 00000000 --text-wrong-color 00000000 --text-clear-color 00000000 --text-caps-lock-color 00000000'

exec swayidle -w \
    timeout 300 "$LOCK" \
    timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' \
    after-resume 'swaymsg "output * dpms on"' \
    before-sleep "$LOCK" \
    lock "$LOCK"
