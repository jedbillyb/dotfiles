#!/bin/bash
# Toggle the VPN, trying transports fastest-first and falling back as each fails.
#
# 1. WireGuard over UDP        - the real thing, lowest overhead.
# 2. AmneziaWG over UDP/123    - still UDP and still full speed. Beats the N4L
#                                school filter, which exempts the NTP port from
#                                its UDP rate cap but fingerprints the WireGuard
#                                handshake. See vpn-amnezia.sh for the details.
# 3. WireGuard over TCP/443    - same VPN, wrapped in a WebSocket by wstunnel.
#                                Needed where even UDP/123 is unusable.
# 4. SSH SOCKS + redsocks      - last resort. Only IPv4 TCP, DNS stays local.
#
# Some networks drop or filter outbound UDP, so WireGuard comes up but never
# handshakes and silently blackholes traffic. Rather than leave that broken
# interface in place, tear it back down and move to the next transport.
#
# Walking that ladder from the top costs HANDSHAKE_TIMEOUT seconds on every
# connect on a network where plain UDP will never work - and those doomed
# handshakes are precisely what the school's DPI watches for. So the transport
# that worked is remembered per network and tried first next time. Everything
# else still falls back in the normal order, and a remembered transport that
# stops working just falls through the rest of the ladder as usual.

HANDSHAKE_TIMEOUT=12
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
PROXY="$SCRIPT_DIR/vpn-proxy.sh"
WSTUNNEL="$SCRIPT_DIR/vpn-wstunnel.sh"
AMNEZIA="$SCRIPT_DIR/vpn-amnezia.sh"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/vpn-toggle-state"
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/vpn-toggle-transports"

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

# Key the memory on the SSID, falling back to the active connection name so
# ethernet and USB tethering still get an entry. Tabs are the field separator,
# so strip them rather than risk a corrupt cache line.
current_net() {
    local net
    net=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    [[ -z "$net" ]] && net=$(nmcli -t -f NAME con show --active 2>/dev/null | head -1)
    printf '%s' "${net//[$'\t\n']/ }"
}

recall_transport() {
    [[ -f "$CACHE_FILE" ]] || return 0
    awk -F'\t' -v n="$1" '$1==n {print $2; exit}' "$CACHE_FILE"
}

remember_transport() {
    local net="$1" t="$2" tmp
    [[ -n "$net" ]] || return 0
    mkdir -p "$(dirname "$CACHE_FILE")"
    tmp=$(mktemp) || return 0
    [[ -f "$CACHE_FILE" ]] && awk -F'\t' -v n="$net" '$1!=n' "$CACHE_FILE" > "$tmp"
    printf '%s\t%s\n' "$net" "$t" >> "$tmp"
    mv "$tmp" "$CACHE_FILE"
}

connected() {
    remember_transport "$NET" "$1"
    notify "$2"
    rm -f "$STATE_FILE"
    refresh_waybar
    exit 0
}

# Tear down whichever transport is active.
if wg_is_up || "$AMNEZIA" status >/dev/null 2>&1 || "$WSTUNNEL" status >/dev/null 2>&1 || "$PROXY" status >/dev/null 2>&1; then
    set_state "disconnecting"
    wg_is_up && sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
    "$AMNEZIA" down >/dev/null 2>&1
    "$WSTUNNEL" down >/dev/null 2>&1
    "$PROXY" down >/dev/null 2>&1
    notify "Disconnected"
    rm -f "$STATE_FILE"
    refresh_waybar
    exit 0
fi

set_state "connecting"
NET="$(current_net)"

try_wg() {
    sudo /usr/bin/wg-quick up wg0 >/dev/null 2>&1 || return 1
    for _ in $(seq 1 $((HANDSHAKE_TIMEOUT * 2))); do
        wg_handshaked && return 0
        sleep 0.5
    done
    # No handshake means UDP is blocked here; don't leave the interface
    # blackholing everything.
    sudo /usr/bin/wg-quick down wg0 >/dev/null 2>&1
    return 1
}

# Each of these verifies DNS and HTTPS through the tunnel before reporting
# success - a handshake alone is not proof the link is usable.
try_awg()   { "$AMNEZIA" up >/dev/null 2>&1; }
try_ws()    { "$WSTUNNEL" up >/dev/null 2>&1; }
try_proxy() { "$PROXY" up >/dev/null 2>&1; }

attempt_msg() {
    case "$1" in
        wg)    echo "Trying WireGuard over UDP..." ;;
        awg)   echo "Trying AmneziaWG on UDP/123..." ;;
        ws)    echo "Trying WireGuard over TCP/443..." ;;
        proxy) echo "Trying SSH tunnel..." ;;
    esac
}

success_msg() {
    case "$1" in
        wg)    echo "Connected - WireGuard (10.0.0.4)" ;;
        awg)   echo "Connected - AmneziaWG UDP/123 (10.0.2.4)" ;;
        ws)    echo "Connected - WireGuard over TCP/443" ;;
        proxy) echo "Connected - SSH tunnel (TCP only, local DNS)" ;;
    esac
}

# Whatever worked here last time goes first; the rest keep their normal order.
ORDER=()
PREFERRED="$(recall_transport "$NET")"
case "$PREFERRED" in
    wg|awg|ws|proxy) ORDER+=("$PREFERRED") ;;
    *)               PREFERRED="" ;;
esac
for t in wg awg ws proxy; do
    [[ "$t" == "$PREFERRED" ]] || ORDER+=("$t")
done

for t in "${ORDER[@]}"; do
    notify "$(attempt_msg "$t")"
    if "try_$t"; then
        connected "$t" "$(success_msg "$t")"
    fi
done

notify "Connection failed"
set_state "failed"
