#!/bin/sh
# Caffeine indicator. swayidle running == idle-lock active == caffeine OFF.
STATE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
if pgrep -x swayidle >/dev/null 2>&1; then
    echo '{"text":"caf off","class":"off"}'
elif [ -f "$STATE" ] && kill -0 "$(cat "$STATE")" 2>/dev/null; then
    echo '{"text":"caf on","class":"on"}'
else
    # idle daemon down but no inhibitor held -- partial/unknown state.
    echo '{"text":"caf on?","class":"on"}'
fi
