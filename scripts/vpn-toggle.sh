#!/bin/bash

if ip link show wg0 &>/dev/null; then
    sudo /usr/bin/wg-quick down wg0
    notify-send -t 3000 "VPN" "Disconnected"
else
    sudo /usr/bin/wg-quick up wg0
    notify-send -t 3000 "VPN" "Connected (10.0.0.4)"
fi

# Refresh the waybar vpn module.
pkill -RTMIN+8 waybar 2>/dev/null
