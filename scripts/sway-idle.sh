#!/bin/sh
# Idle/lock daemon for sway. Factored into its own script so the caffeine
# toggle (caffeine-toggle.sh) can cleanly stop and restart it.
exec swayidle -w \
    timeout 300 '/home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000' \
    timeout 600 'swaymsg "output * dpms off"' \
    after-resume 'swaymsg "output * dpms on"' \
    before-sleep '/home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000' \
    lock '/home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000'
