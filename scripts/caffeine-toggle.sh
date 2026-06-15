#!/bin/sh
# Toggle "caffeine" / stay-awake mode (manual).
#
# Authoritative signal: whether swayidle is running.
#   caffeine ON  = swayidle stopped + elogind inhibitor held
#   caffeine OFF = swayidle running + no inhibitor
#
# The toggle reconciles the REAL state on every press, so it self-heals if
# swayidle was restarted (e.g. after a sway restart) while a stale pidfile
# still claimed "on" -- the old failure mode where waybar showed "caf on"
# but the screen kept locking/blanking.
#
# Inhibitor PID is tracked in $XDG_RUNTIME_DIR/caffeine.pid.

STATE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
SWAYIDLE=/home/jed/.local/bin/sway-idle.sh

inhibitor_alive() {
    [ -f "$STATE" ] && kill -0 "$(cat "$STATE")" 2>/dev/null
}

stop_inhibitor() {
    inhibitor_alive && kill "$(cat "$STATE")" 2>/dev/null
    rm -f "$STATE"
}

start_inhibitor() {
    inhibitor_alive && return   # already held; don't stack inhibitors
    elogind-inhibit --what=handle-lid-switch:sleep:idle \
        --who=caffeine --why="stay awake (manual)" --mode=block \
        sleep infinity &
    echo $! > "$STATE"
}

if pgrep -x swayidle >/dev/null 2>&1; then
    # ── swayidle running => currently OFF => turn ON ─────────────────────────────
    pkill -x swayidle 2>/dev/null
    start_inhibitor
    notify-send -t 1500 "Caffeine on" "Staying awake — lid close ignored"
else
    # ── swayidle stopped => currently ON => turn OFF ────────────────────────────
    stop_inhibitor
    pkill -x swayidle 2>/dev/null          # belt-and-braces: drop any stray instance
    "$SWAYIDLE" &                          # restart exactly one clean instance
    notify-send -t 1500 "Caffeine off" "Idle lock & lid suspend re-enabled"
fi

# Refresh the waybar caffeine module.
pkill -RTMIN+9 waybar 2>/dev/null
