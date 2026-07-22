#!/bin/bash
# Waybar custom network module: signal % for the ACTIVE wifi adapter (whichever
# holds the default route).

iface="$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')"

if [ -z "$iface" ] || [ ! -d "/sys/class/net/$iface/wireless" ]; then
    echo '{"text":"wifi off","class":"disconnected"}'
    exit 0
fi

# signal % of the active AP
sig="$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')"
[ -z "$sig" ] && sig="?"

printf '{"text":"wifi %3s%%","class":"connected"}\n' "$sig"
