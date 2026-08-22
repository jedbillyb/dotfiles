#!/bin/bash
# Waybar VPN module. Reports *which transport* is carrying the tunnel, not just
# on/off: vpn-toggle.sh falls back through four of them and they differ hugely
# in behaviour, so "which one landed" is the first thing worth knowing when the
# connection feels wrong.
#
# Colour is the quick signal - green means a native UDP tunnel, amber means a
# degraded fallback that still works.
#
# Everything in the tooltip is read from the live system: the endpoint from the
# facts file the connect scripts drop at handshake time, the transport port from
# that endpoint, and full-vs-split from the routing table. Nothing here is
# written down twice, so changing the endpoint in a config changes the tooltip
# with no edit to this file.
PROXY="$HOME/.local/bin/vpn-proxy.sh"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/vpn-toggle-state"
# Where the connect scripts record what they actually dialled. They run with
# sudo at that moment; waybar does not, and `wg show` needs root, so the answer
# has to be left behind rather than asked for.
FACTS_DIR="${XDG_RUNTIME_DIR:-/tmp}/vpn-facts"

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

# host:port of the live peer, or empty. Only trusted while the interface it
# describes is actually up - down() removes the file, but a crash might not.
endpoint_of() {
    local f="$FACTS_DIR/$1.facts" ep=""
    [[ -r "$f" ]] && ep=$(awk -F= '$1=="endpoint"{print $2; exit}' "$f")
    printf '%s' "$ep"
}

# "UDP/123" and friends, derived from the endpoint rather than asserted.
port_of() {
    local ep="$1"
    [[ "$ep" == *:* ]] || return 0
    printf 'UDP/%s' "${ep##*:}"
}

# Full tunnel or Microsoft 365 split? wg-quick installs a default route for
# 0.0.0.0/0 and a pile of specific routes for anything narrower, so the routing
# table answers this without reading a config we cannot read anyway.
scope_of() {
    local ifc="$1" n
    if ip -4 route show table all 2>/dev/null | grep -qE "^default .*dev $ifc"; then
        printf 'full tunnel'
        return
    fi
    n=$(ip -4 route show dev "$ifc" 2>/dev/null | grep -vc 'proto kernel')
    if (( n > 1 )); then
        printf 'split tunnel - %d routes inside, everything else direct' "$n"
    else
        printf 'full tunnel'
    fi
}

# Assemble a tooltip from whichever facts exist. A line whose value is unknown
# is dropped rather than guessed, so the tooltip is never confidently wrong.
tip() {
    local out=""
    for line in "$@"; do
        [[ -n "$line" ]] || continue
        [[ -n "$out" ]] && out+="\n"
        out+="$line"
    done
    printf '%s' "$out"
}

emit() { printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$1" "$2" "$3"; exit 0; }

# Order matters: check the specific interfaces before the generic wireguard
# type. awg0 is a userspace TUN (amneziawg-go), so it never matches
# 'ip link show type wireguard' - checking by name is what makes it visible.
if ip link show wg-tcp &>/dev/null; then
    ep=$(endpoint_of wg-tcp)
    emit "vpn ws" "degraded" "$(tip \
        "WireGuard tunnelled over TCP (wstunnel)" \
        "interface wg-tcp $(ifaddr wg-tcp)" \
        "${ep:+endpoint $ep}" \
        "$(scope_of wg-tcp)" \
        "fallback: native UDP was blocked here")"
elif ip link show awg0 &>/dev/null; then
    ep=$(endpoint_of awg0)
    emit "vpn awg" "on" "$(tip \
        "AmneziaWG${ep:+ over $(port_of "$ep")}" \
        "interface awg0 $(ifaddr awg0)" \
        "${ep:+endpoint $ep}" \
        "$(scope_of awg0)")"
elif ip link show wg0 &>/dev/null; then
    ep=$(endpoint_of wg0)
    emit "vpn wg" "on" "$(tip \
        "WireGuard${ep:+ over $(port_of "$ep")}" \
        "interface wg0 $(ifaddr wg0)" \
        "${ep:+endpoint $ep}" \
        "$(scope_of wg0)")"
elif [[ -x "$PROXY" ]] && "$PROXY" status >/dev/null 2>&1; then
    emit "vpn ssh" "proxy" "$(tip \
        "SSH SOCKS + redsocks" \
        "last resort: IPv4 TCP only, DNS stays local")"
else
    emit "vpn off" "off" "no tunnel"
fi
