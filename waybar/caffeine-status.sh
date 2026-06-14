#!/bin/sh
STATE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.pid"
if [ -f "$STATE" ] && kill -0 "$(cat "$STATE")" 2>/dev/null; then
    echo '{"text":"caf on","class":"on"}'
else
    echo '{"text":"caf off","class":"off"}'
fi
