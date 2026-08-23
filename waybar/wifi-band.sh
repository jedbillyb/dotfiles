#!/bin/bash
# Waybar module: which band the WiFi is actually on, and whether it is pinned there.
#
# The onboard mt7921e is a WiFi+Bluetooth combo chip, so 2.4 GHz shares the radio
# with Bluetooth. With a permanent BLE link up (ancs4linux talking to the iPhone)
# 2.4 GHz throughput collapses - measured 0.00 Mbit/s on 2.4 GHz against
# 80 Mbit/s on 5 GHz, same room, minutes apart. Band steering hands the client
# back to 2.4 GHz whenever 5 GHz gets weak, so "the internet died" is usually
# "the router moved me to 2.4 GHz again". This module makes that visible and
# lets the band be pinned.
#
# Click cycles: auto -> 5 GHz -> 2.4 GHz -> auto.
# NetworkManager expresses this as 802-11-wireless.band: "" / "a" / "bg".

SIGNAL=13

active_conn() {
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null |
        awk -F: '$2 ~ /wireless/{print $1; exit}'
}

active_dev() {
    nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null |
        awk -F: '$2=="wifi" && $3=="connected"{print $1; exit}'
}

# "" (auto) | a (5 GHz) | bg (2.4 GHz)
locked_band() {
    nmcli -g 802-11-wireless.band connection show "$1" 2>/dev/null
}

notify() { command -v notify-send >/dev/null && notify-send -a wifi-band "$1" "$2"; }

refresh() { pkill -RTMIN+$SIGNAL waybar 2>/dev/null; }

status() {
    local dev conn freq band lock adapter text classes
    dev="$(active_dev)"
    conn="$(active_conn)"

    if [ -z "$dev" ]; then
        echo '{"text":"wifi off","class":"disconnected","tooltip":"No WiFi connection"}'
        return
    fi

    freq="$(iw dev "$dev" link 2>/dev/null | awk '/freq:/{print $2; exit}')"
    if [ -z "$freq" ]; then
        echo '{"text":"wifi off","class":"disconnected","tooltip":"No WiFi connection"}'
        return
    fi

    if [ "${freq%%.*}" -gt 5000 ]; then band="5G"; else band="2.4G"; fi

    lock="$(locked_band "$conn")"
    case "$lock" in
        a)  lock_txt="lock"; lock_cls="lock"; want="5 GHz" ;;
        bg) lock_txt="lock"; lock_cls="lock"; want="2.4 GHz" ;;
        *)  lock_txt="auto"; lock_cls="auto"; want="auto (band steering)" ;;
    esac

    # The USB adapter exists specifically to free the mt7921 from BT coexistence,
    # so it is worth showing when it is the one carrying traffic.
    adapter=""
    if readlink -f "/sys/class/net/$dev/device" 2>/dev/null | grep -q '/usb'; then
        adapter="usb "
    fi

    text="${adapter}${band} ${lock_txt}"
    if [ "$band" = "5G" ]; then classes='"band5"'; else classes='"band24"'; fi
    classes="[$classes,\"$lock_cls\"]"

    local sig rate tip
    sig="$(iw dev "$dev" link 2>/dev/null | awk '/signal:/{print $2" dBm"; exit}')"
    rate="$(iw dev "$dev" link 2>/dev/null | awk '/tx bitrate:/{print $3" "$4; exit}')"
    tip="$dev on ${freq%.*} MHz ($band)\\nsignal ${sig:-?}   tx ${rate:-?}\\npreference: $want\\nclick to cycle auto / 5 GHz / 2.4 GHz"

    printf '{"text":"%s","class":%s,"tooltip":"%s"}\n' "$text" "$classes" "$tip"
}

toggle() {
    local conn cur next label
    conn="$(active_conn)"
    if [ -z "$conn" ]; then
        notify "WiFi band" "No active WiFi connection to pin."
        return 1
    fi

    cur="$(locked_band "$conn")"
    case "$cur" in
        "")  next="a";  label="5 GHz only" ;;
        a)   next="bg"; label="2.4 GHz only" ;;
        *)   next="";   label="auto (band steering)" ;;
    esac

    nmcli connection modify "$conn" 802-11-wireless.band "$next" 2>/dev/null || {
        notify "WiFi band" "Could not change band preference."
        return 1
    }

    notify "WiFi band" "Switching to $label..."
    refresh

    # Reactivating is what actually moves the client to the other radio.
    if ! nmcli connection up "$conn" >/dev/null 2>&1; then
        # Pinning to a band with no usable AP leaves us offline - undo it rather
        # than stranding the machine with no network.
        nmcli connection modify "$conn" 802-11-wireless.band "$cur" 2>/dev/null
        nmcli connection up "$conn" >/dev/null 2>&1
        notify "WiFi band" "$label unavailable here - reverted."
        refresh
        return 1
    fi

    notify "WiFi band" "Now $label."
    refresh
}

case "$1" in
    toggle) toggle ;;
    *)      status ;;
esac
