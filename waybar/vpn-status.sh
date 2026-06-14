#!/bin/bash
if ip link show type wireguard 2>/dev/null | grep -q 'wg'; then
    echo "vpn on"
else
    echo "vpn off"
fi
