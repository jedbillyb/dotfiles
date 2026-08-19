#!/bin/bash
# Waybar VPN module. Reports *which transport* is carrying the tunnel, not just
# on/off: vpn-toggle.sh falls back through four of them and they differ hugely
# in speed, so "which one landed" is the first thing worth knowing when the
# connection feels wrong. Measured on the school wifi: wg/awg ~110 Mbit/s,
# wstunnel ~33 Mbit/s, ssh proxy is TCP-only with local DNS.
#
# Colour is the quick signal - green means a full-speed UDP tunnel, amber means
# a degraded fallback that still works.
PROXY="$HOME/.local/bin/vpn-proxy.sh"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/vpn-toggle-state"

state=""
[[ -f "$STATE_FILE" ]] && state="$(<"$STATE_FILE")"

case "$state" in
    connecting)
        echo '{"text":"vpn connecting...","class":"connecting"}'
        exit 0
        ;;
    disconnecting)
        echo '{"text":"vpn disconnecting...","class":"connecting"}'
        exit 0
        ;;
    failed)
        echo '{"text":"vpn failed","class":"failed"}'
        exit 0
        ;;
esac

# Tunnel address, so the tooltip shows which peer identity is in use.
ifaddr() { ip -4 -br addr show "$1" 2>/dev/null | awk '{print $3}' | cut -d/ -f1; }

emit() { printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$1" "$2" "$3"; exit 0; }

# Order matters: check the specific interfaces before the generic wireguard
# type. awg0 is a userspace TUN (amneziawg-go), so it never matches
# 'ip link show type wireguard' - checking by name is what makes it visible.
if ip link show wg-tcp &>/dev/null; then
    emit "vpn ws" "degraded" \
        "WireGuard over TCP/443 (wstunnel)\ninterface wg-tcp $(ifaddr wg-tcp)\nfallback: UDP and UDP/123 both failed here\n~33 Mbit/s - TCP-over-TCP"
elif ip link show awg0 &>/dev/null; then
    emit "vpn awg" "on" \
        "AmneziaWG over UDP/123\ninterface awg0 $(ifaddr awg0)\nendpoint 152.69.172.139:123\nbeats the school DPI - full UDP speed"
elif ip link show wg0 &>/dev/null; then
    emit "vpn wg" "on" \
        "WireGuard over UDP/51820\ninterface wg0 $(ifaddr wg0)\nendpoint 152.69.172.139:51820"
elif [[ -x "$PROXY" ]] && "$PROXY" status >/dev/null 2>&1; then
    emit "vpn ssh" "proxy" \
        "SSH SOCKS + redsocks\nlast resort: IPv4 TCP only, DNS stays local"
else
    emit "vpn off" "off" "no tunnel"
fi
