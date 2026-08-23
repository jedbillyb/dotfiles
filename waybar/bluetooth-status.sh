#!/bin/bash
# Waybar module: Bluetooth power state and how many devices are connected,
# with a click to toggle the controller.
#
# This sits next to the WiFi band module on purpose. Bluetooth and 2.4 GHz WiFi
# share one radio on the onboard mt7921e, and the ancs4linux iPhone notification
# link keeps a BLE connection up permanently. When the band module says 2.4G,
# an active BLE link here is the thing wrecking throughput - so the two are
# read together, and this is the other half of the fix.
#
# Turning Bluetooth off also drops iPhone notifications (ancs4linux) and any
# AirPods/headset audio, which is why it is a deliberate click and not automatic.
#
# This uses rfkill, NOT `bluetoothctl power off`, because power-off does not
# stick on this machine. Three things race to switch the adapter back on within
# a minute: ancs4linux-watchdog re-arms the BLE advert every 30s (its
# `discoverable on` powers the controller as a side effect), ancs4linux-reconnect
# runs `bluetoothctl connect` on the bonded iPhone every 60s, and
# /etc/bluetooth/main.conf has AutoEnable=true. A soft rfkill block sits below
# all of them - BlueZ cannot power up a blocked controller, so the toggle holds.
# Verified off for 100s straight, across three watchdog cycles.
#
# Side effect worth knowing: while blocked, ancs4linux-watchdog logs a failed
# re-arm every 30s to /var/log/ancs4linux-watchdog. Harmless, but that log is
# not evidence of a fault when the toggle is deliberately off.

SIGNAL=14

bt() { timeout 3 bluetoothctl "$@" 2>/dev/null; }

refresh() { pkill -RTMIN+$SIGNAL waybar 2>/dev/null; }

powered() { bt show | grep -q "Powered: yes"; }

# Soft-blocked at the rfkill layer, i.e. switched off by this module rather than
# merely unpowered. Checked first because a blocked controller also reads
# "Powered: no", and the two want different tooltips and a different toggle.
blocked() { rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; }

status() {
    local names count text class tip

    if ! bt show | grep -q "Powered:"; then
        echo '{"text":"bt n/a","class":"missing","tooltip":"No Bluetooth controller"}'
        return
    fi

    if blocked; then
        echo '{"text":"bt off","class":"off","tooltip":"Bluetooth blocked (rfkill)\n2.4 GHz WiFi has the radio to itself\niPhone notifications and headset audio are off\nclick to turn back on"}'
        return
    fi

    if ! powered; then
        echo '{"text":"bt off","class":"off","tooltip":"Bluetooth not powered\nclick to turn on"}'
        return
    fi

    names="$(bt devices Connected | sed 's/^Device [0-9A-F:]* //')"
    count="$(printf '%s' "$names" | grep -c .)"

    if [ "$count" -gt 0 ]; then
        text="bt $count"
        class="connected"
        tip="Bluetooth on, $count connected:\\n$(printf '%s' "$names" | paste -sd'|' - | sed 's/|/\\n/g')\\nshares the radio with 2.4 GHz WiFi\\nclick to turn off"
    else
        text="bt on"
        class="on"
        tip="Bluetooth on, nothing connected\\nclick to turn off"
    fi

    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$class" "$tip"
}

toggle() {
    if blocked; then
        rfkill unblock bluetooth
        # Unblocking alone leaves the controller down; AutoEnable would get
        # there eventually, but not fast enough for a click to feel like it did
        # anything.
        sleep 1
        bt power on >/dev/null
    else
        rfkill block bluetooth
    fi
    refresh
}

case "$1" in
    toggle) toggle ;;
    *)      status ;;
esac
