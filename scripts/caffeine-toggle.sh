#!/bin/sh
# Toggle "caffeine" / stay-awake mode.
#
# ON:  stops swayidle (no idle lock / DPMS off) and holds an elogind inhibitor
#      so closing the lid no longer suspends the machine.
# OFF: releases the inhibitor and restarts swayidle.
#
# State is the PID of the held inhibitor, in $XDG_RUNTIME_DIR/caffeine.pid.

STATE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"

is_on() {
    [ -f "$STATE" ] && kill -0 "$(cat "$STATE")" 2>/dev/null
}

if is_on; then
    # ── Turn OFF ──────────────────────────────────────────────────────────────
    kill "$(cat "$STATE")" 2>/dev/null
    rm -f "$STATE"
    pkill -x swayidle
    /home/jed/.local/bin/sway-idle.sh &
    notify-send -t 1500 "Caffeine off" "Idle lock & lid suspend re-enabled"
else
    # ── Turn ON ───────────────────────────────────────────────────────────────
    pkill -x swayidle
    elogind-inhibit --what=handle-lid-switch:sleep:idle \
        --who=caffeine --why="stay awake (manual)" --mode=block \
        sleep infinity &
    echo $! > "$STATE"
    notify-send -t 1500 "Caffeine on" "Staying awake — lid close ignored"
fi

# Refresh the waybar caffeine module.
pkill -RTMIN+9 waybar 2>/dev/null
