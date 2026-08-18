#!/bin/bash
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

# wg-tcp is the same VPN carried over TCP/443, so it is still a full tunnel -
# but worth distinguishing in the bar, since it means UDP is blocked here.
if ip link show wg-tcp &>/dev/null; then
    echo '{"text":"vpn ws","class":"on"}'
elif ip link show type wireguard 2>/dev/null | grep -q 'wg'; then
    echo '{"text":"vpn on","class":"on"}'
elif [[ -x "$PROXY" ]] && "$PROXY" status >/dev/null 2>&1; then
    echo '{"text":"vpn tcp","class":"proxy"}'
else
    echo '{"text":"vpn off","class":"off"}'
fi
