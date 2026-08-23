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

SIGNAL=14

bt() { timeout 3 bluetoothctl "$@" 2>/dev/null; }

refresh() { pkill -RTMIN+$SIGNAL waybar 2>/dev/null; }

powered() { bt show | grep -q "Powered: yes"; }

status() {
    local names count text class tip

    if ! bt show | grep -q "Powered:"; then
        echo '{"text":"bt n/a","class":"missing","tooltip":"No Bluetooth controller"}'
        return
    fi

    if ! powered; then
        echo '{"text":"bt off","class":"off","tooltip":"Bluetooth off\n2.4 GHz WiFi has the radio to itself\nclick to turn on"}'
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
    if powered; then
        bt power off >/dev/null
    else
        bt power on >/dev/null
    fi
    refresh
}

case "$1" in
    toggle) toggle ;;
    *)      status ;;
esac
