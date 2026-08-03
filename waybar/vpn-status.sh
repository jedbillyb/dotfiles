#!/bin/bash
PROXY="$HOME/.local/bin/vpn-proxy.sh"

if ip link show type wireguard 2>/dev/null | grep -q 'wg'; then
    echo '{"text":"vpn on","class":"on"}'
elif [[ -x "$PROXY" ]] && "$PROXY" status >/dev/null 2>&1; then
    echo '{"text":"vpn tcp","class":"proxy"}'
else
    echo '{"text":"vpn off","class":"off"}'
fi
