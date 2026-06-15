#!/bin/sh
# Idle/lock daemon for sway. Factored into its own script so the caffeine
# toggle (caffeine-toggle.sh) can cleanly stop and restart it.

# Kill fprintd before locking so the lock screen always starts from a fresh
# cold TLS handshake. The driver keeps the sensor's TLS session warm across
# verify retries for speed, but a session left idle (e.g. across a lock) can go
# stale and make every scan fail in a "Wrong" loop. Restarting fprintd here
# forces a clean handshake on the first scan. Needs passwordless sudo (fprintd
# runs as root): see /etc/sudoers.d for the NOPASSWD pkill rule. -n so it never
# blocks the lock waiting for a password; 2>/dev/null swallows "no process".
LOCK='sudo -n pkill -9 -x fprintd 2>/dev/null; /home/jed/.local/bin/swaylock-fprintd --fingerprint -c 000000'

exec swayidle -w \
    timeout 300 "$LOCK" \
    timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' \
    after-resume 'swaymsg "output * dpms on"' \
    before-sleep "$LOCK" \
    lock "$LOCK"
