#!/bin/bash
# Show an indicator when the active WiFi connection is running over a USB adapter.
# Onboard mt7921 is on PCI; the AR9271 USB adapter shows up with "usb" in its
# sysfs device path. NetworkManager failover prefers the USB adapter when present.

usb_active=""
for dev in $(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '$2=="wifi" && $3=="connected"{print $1}'); do
    if readlink -f "/sys/class/net/$dev/device" 2>/dev/null | grep -q '/usb'; then
        usb_active="$dev"
        break
    fi
done

if [ -n "$usb_active" ]; then
    echo '{"text":"usb wifi","class":"on"}'
else
    echo '{"text":"onboard wifi","class":"off"}'
fi
