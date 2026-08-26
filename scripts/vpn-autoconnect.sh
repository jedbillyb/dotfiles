#!/bin/bash
# vpn-autoconnect.sh - bring the AmneziaWG tunnel up on its own, on the
# networks that need it, so the VPN stops being something to remember at every
# boot, wake and reconnect.
#
# Called from three places, each with its own argument shape:
#   NetworkManager dispatcher   $1 = interface   $2 = up|down|dhcp4-change|...
#   elogind system-sleep hook   $1 = pre|post    $2 = suspend|hibernate|...
#   by hand                     no arguments
#
# Only the SSIDs in AUTO_NETS get this treatment; everywhere else the VPN stays
# a deliberate mod+Shift+v decision. On those networks plain WireGuard can
# never handshake (see vpn-amnezia.sh for the packet-level reason), so this
# goes straight to AmneziaWG on UDP/123 instead of walking vpn-toggle.sh's
# ladder and spending HANDSHAKE_TIMEOUT seconds failing at the top of it.
#
# A manual disconnect wins for INHIBIT_TTL. vpn-toggle.sh stamps INHIBIT when
# it tears the tunnel down by hand, and this refuses to act while that stamp is
# fresh - otherwise turning the VPN off to reach the school printers
# (10.1.1.12, unreachable through the full tunnel) would be undone by the next
# resume. The stamp expires rather than latching, so a laptop that was put to
# sleep with the VPN off still comes back protected the next day.
#
# NetworkManager kills a dispatcher script that runs long, and a connect takes
# tens of seconds, so the hook paths re-exec themselves detached and return
# immediately.

set -uo pipefail

AUTO_NETS=("Karamu Devices")

INHIBIT_TTL=3600     # 1h
WIFI_WAIT=30         # seconds to let the link finish coming up after resume

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# The dispatcher copy lives in /etc, away from its siblings, so fall back to
# the stable symlink farm in ~/.local/bin.
AMNEZIA="$SCRIPT_DIR/vpn-amnezia.sh"
[[ -x "$AMNEZIA" ]] || AMNEZIA="/home/jed/.local/bin/vpn-amnezia.sh"

# These hooks run as root, where XDG_RUNTIME_DIR is unset. Point it at the
# session's own runtime dir anyway: vpn-amnezia.sh writes the endpoint facts
# there for the unprivileged waybar module, and would otherwise drop them in
# /tmp where waybar never looks.
SESSION_UID=1000
SESSION_USER=jed
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$SESSION_UID}"
INHIBIT="$XDG_RUNTIME_DIR/vpn-autoconnect-off"
LOCK="/run/vpn-autoconnect.lock"

# This box runs no syslog daemon, so logger would write into the void. Land
# next to vpn-amnezia.sh's own diagnostics instead - a failed auto-connect is
# invisible by definition, and the two logs are read together.
LOG="/tmp/vpn-amnezia/autoconnect.log"

log() {
    mkdir -p "$(dirname "$LOG")"
    printf '%s %s\n' "$(date -Is)" "$1" >>"$LOG"
}

notify() {
    runuser -u "$SESSION_USER" -- env \
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$SESSION_UID/bus" \
        notify-send -t 3000 "VPN" "$1" 2>/dev/null
}

current_net() {
    nmcli -t -f active,ssid dev wifi 2>/dev/null |
        awk -F: '$1=="yes"{print $2; exit}'
}

vpn_up() {
    ip link show wg0 &>/dev/null ||
        ip link show wg-tcp &>/dev/null ||
        "$AMNEZIA" status >/dev/null 2>&1
}

inhibited() {
    local stamp
    stamp=$(cat "$INHIBIT" 2>/dev/null) || return 1
    [[ "$stamp" =~ ^[0-9]+$ ]] || return 1
    (( stamp + INHIBIT_TTL > $(date +%s) ))
}

wanted_here() {
    local net="$1" n
    for n in "${AUTO_NETS[@]}"; do
        [[ "$net" == "$n" ]] && return 0
    done
    return 1
}

connect() {
    # One at a time: NetworkManager happily fires several events for a single
    # reconnect, and two awg-quick runs racing each other leave a half-built
    # interface behind.
    exec 9>"$LOCK"
    flock -n 9 || exit 0

    local net deadline=$(( $(date +%s) + WIFI_WAIT ))
    # After resume the radio is usually still reassociating, so the SSID and
    # the default route arrive a few seconds late. Wait for them rather than
    # declaring the network uninteresting.
    while :; do
        net="$(current_net)"
        wanted_here "$net" && break
        (( $(date +%s) < deadline )) || exit 0
        sleep 2
    done

    vpn_up && exit 0
    inhibited && { log "skipping $net: turned off by hand"; exit 0; }

    log "connecting AmneziaWG on $net"
    if "$AMNEZIA" up >/dev/null 2>&1; then
        # The endpoint facts were just written by root into the user's runtime
        # dir. Hand them back, or the next by-hand connect cannot truncate its
        # own file and the waybar tooltip quietly stops tracking reality.
        [[ $(id -u) -eq 0 ]] &&
            chown -R "$SESSION_USER" "$XDG_RUNTIME_DIR/vpn-facts" 2>/dev/null
        log "connected"
        notify "Connected - AmneziaWG UDP/123 (10.0.2.4)"
    else
        log "failed - see 'vpn-amnezia.sh diag'"
        notify "Auto-connect failed - try mod+Shift+v"
    fi
    pkill -RTMIN+8 waybar 2>/dev/null
}

# Decide whether this particular invocation is worth acting on, then hand off
# to a detached copy so NetworkManager is not left waiting on a connect.
case "${1:-}" in
    # elogind: only the wake half matters.
    pre)  exit 0 ;;
    post) ;;
    # Manual run.
    "") ;;
    --run) connect; exit 0 ;;
    # NetworkManager: $2 is the action. Only a fresh activation is a reason to
    # connect; the dhcp/connectivity churn that follows would re-connect a
    # tunnel the user had just switched off, and the VPN's own interface
    # coming up must not feed back into here.
    *)
        [[ "${2:-}" == "up" ]] || exit 0
        [[ -e "/sys/class/net/$1/wireless" ]] || exit 0
        ;;
esac

setsid "$(readlink -f "$0")" --run >/dev/null 2>&1 &
exit 0
