#!/bin/sh
# Notification mode indicator + toggle for waybar. Three modes:
#
#   full    everything shows
#   iphone  only ANCS notifications from the phone; local apps are suppressed
#   dnd     nothing shows (dunst paused; notifications still reach history)
#
# "iphone" is the mute_local/allow_iphone rule pair in dunstrc, not a dunst
# feature -- see the comment there.
set -eu

STATE="${XDG_RUNTIME_DIR:-/tmp}/notification-mode"

read_mode() {
    [ -f "$STATE" ] && cat "$STATE" || echo full
}

apply() {
    case "$1" in
        dnd)
            dunstctl set-paused true
            ;;
        iphone)
            dunstctl set-paused false
            dunstctl rule mute_local enable
            ;;
        *)
            dunstctl set-paused false
            dunstctl rule mute_local disable
            ;;
    esac
    printf '%s' "$1" > "$STATE"
}

case "${1:-status}" in
    toggle)
        case "$(read_mode)" in
            full)   next=iphone ;;
            iphone) next=dnd ;;
            *)      next=full ;;
        esac
        apply "$next"
        # waybar re-runs this script on signal rather than polling.
        pkill -RTMIN+7 waybar 2>/dev/null || true
        ;;
    status)
        mode=$(read_mode)
        # dunst can be paused behind our back (dunstctl, another script), so
        # trust dunst over the state file when the two disagree.
        if [ "$(dunstctl is-paused 2>/dev/null)" = "true" ] && [ "$mode" != dnd ]; then
            mode=dnd
            printf '%s' "$mode" > "$STATE"
        fi
        case "$mode" in
            dnd)    printf '{"text":"dnd","class":"dnd","tooltip":"Notifications silenced"}\n' ;;
            iphone) printf '{"text":"notif phone","class":"iphone","tooltip":"iPhone notifications only"}\n' ;;
            *)      printf '{"text":"notif all","class":"full","tooltip":"All notifications"}\n' ;;
        esac
        ;;
esac
