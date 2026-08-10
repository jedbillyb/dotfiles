#!/bin/bash
# Toggle the VPN, preferring WireGuard and falling back to the SSH/TCP tunnel.
#
# Some networks (school/guest hotspots) drop all outbound UDP, so WireGuard
# comes up but never handshakes and silently blackholes traffic. Rather than
# leave that broken interface in place, tear it back down and use vpn-proxy.sh,
# which tunnels over TCP instead.

HANDSHAKE_TIMEOUT=12
PROXY="$(dirname "$(readlink -f "$0")")/vpn-proxy.sh"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/vpn-toggle-state"

notify() {
    notify-send -t 3000 "VPN" "$1" 2>/dev/null
}

refresh_waybar() {
    pkill -RTMIN+8 waybar 2>/dev/null
}

set_state() {
    echo -n "$1" > "$STATE_FILE"
    refresh_waybar
}

wg_is_up() {
    ip link show wg0 &>/dev/null
}

wg_handshaked() {
    local hs
    hs=$(sudo /usr/bin/wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
    [[ -n "$hs" && "$hs" != "0" ]]
}

# Tear down whichever transport is active.
if wg_is_up || "$PROXY" status >/dev/null 2>&1; then
    set_state "disconnecting"
    wg_is_up && sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
    "$PROXY" down >/dev/null 2>&1
    notify "Disconnected"
    rm -f "$STATE_FILE"
    refresh_waybar
    exit 0
fi

set_state "connecting"

if sudo /usr/bin/wg-quick up wg0 >/dev/null 2>&1; then
    for _ in $(seq 1 $((HANDSHAKE_TIMEOUT * 2))); do
        if wg_handshaked; then
            notify "Connected - WireGuard (10.0.0.4)"
            rm -f "$STATE_FILE"
            refresh_waybar
            exit 0
        fi
        sleep 0.5
    done
    # No handshake means UDP is blocked here; don't leave the interface
    # blackholing everything.
    sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
fi

notify "WireGuard blocked, trying TCP fallback..."
if "$PROXY" up >/dev/null 2>&1; then
    notify "Connected - SSH tunnel (UDP blocked here)"
    rm -f "$STATE_FILE"
else
    notify "Connection failed"
    set_state "failed"
    exit 0
fi
refresh_waybar
