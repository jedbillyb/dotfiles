#!/bin/bash
# Toggle the VPN, trying transports fastest-first and falling back as each fails.
#
# 1. WireGuard over UDP        - the real thing, lowest overhead.
# 2. WireGuard over TCP/443    - same VPN, wrapped in a WebSocket by wstunnel.
#                                Needed on networks (N4L/school) that filter UDP.
# 3. SSH SOCKS + redsocks      - last resort. Only IPv4 TCP, DNS stays local.
#
# Some networks drop or filter outbound UDP, so WireGuard comes up but never
# handshakes and silently blackholes traffic. Rather than leave that broken
# interface in place, tear it back down and move to the next transport.

HANDSHAKE_TIMEOUT=12
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROXY="$SCRIPT_DIR/vpn-proxy.sh"
WSTUNNEL="$SCRIPT_DIR/vpn-wstunnel.sh"
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

connected() {
    notify "$1"
    rm -f "$STATE_FILE"
    refresh_waybar
    exit 0
}

# Tear down whichever transport is active.
if wg_is_up || "$WSTUNNEL" status >/dev/null 2>&1 || "$PROXY" status >/dev/null 2>&1; then
    set_state "disconnecting"
    wg_is_up && sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
    "$WSTUNNEL" down >/dev/null 2>&1
    "$PROXY" down >/dev/null 2>&1
    notify "Disconnected"
    rm -f "$STATE_FILE"
    refresh_waybar
    exit 0
fi

set_state "connecting"

if sudo /usr/bin/wg-quick up wg0 >/dev/null 2>&1; then
    for _ in $(seq 1 $((HANDSHAKE_TIMEOUT * 2))); do
        wg_handshaked && connected "Connected - WireGuard (10.0.0.4)"
        sleep 0.5
    done
    # No handshake means UDP is blocked here; don't leave the interface
    # blackholing everything.
    sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
fi

# Still a full tunnel, just carried over TCP/443. vpn-wstunnel.sh verifies DNS
# and HTTPS through the tunnel before reporting success, and tears itself down
# if it can't - a handshake alone is not proof the link is usable.
notify "UDP blocked, trying WireGuard over TCP..."
if "$WSTUNNEL" up >/dev/null 2>&1; then
    connected "Connected - WireGuard over TCP/443"
fi

notify "Trying SSH tunnel..."
if "$PROXY" up >/dev/null 2>&1; then
    connected "Connected - SSH tunnel (TCP only, local DNS)"
fi

notify "Connection failed"
set_state "failed"
