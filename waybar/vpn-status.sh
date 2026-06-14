#!/bin/bash
if ip link show type wireguard 2>/dev/null | grep -q 'wg'; then
    echo '{"text":"vpn on","class":"on"}'
else
    echo '{"text":"vpn off","class":"off"}'
fi
