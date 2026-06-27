#!/bin/bash
# Compare WiFi adapters by latency/jitter/link-rate/signal.
#
# The failover setup keeps only one adapter connected at a time, so the usual
# workflow is: run this now, then plug/unplug the USB adapter and run it again.
# If both adapters happen to be connected, they're measured side by side.
#
# Latency is what separates these adapters (onboard mt7921 has bad jitter; the
# AR9271 USB adapter is much lower) — not throughput. See the wifi-failover notes.

TARGET="${1:-1.1.1.1}"   # ping target; override with an arg
COUNT=20                  # pings per adapter

label() {
    case "$1" in
        wlp2s0) echo "onboard (mt7921)";;
        wlp4s0f4u2|wlp*u*) echo "USB (AR9271)";;
        *) echo "$1";;
    esac
}

measure() {
    local dev="$1"
    local name; name="$(label "$dev")"

    local link signal
    link="$(iw dev "$dev" link 2>/dev/null | awk '/tx bitrate/{print $3" "$4}')"
    signal="$(iw dev "$dev" link 2>/dev/null | awk '/signal:/{print $2" "$3}')"

    # bind ping to the interface so we test THIS adapter, not the default route
    local out stats
    out="$(ping -I "$dev" -c "$COUNT" -i 0.2 -W 1 "$TARGET" 2>/dev/null)"
    stats="$(echo "$out" | awk -F'/' '/rtt|round-trip/{print $5" "$6" "$7}')"
    local avg max mdev loss
    avg="$(echo "$stats" | awk '{print $1}')"
    max="$(echo "$stats" | awk '{print $2}')"
    mdev="$(echo "$stats" | awk '{print $3}')"
    loss="$(echo "$out" | grep -oE '[0-9]+% packet loss' | grep -oE '[0-9]+%')"

    printf "%-18s  avg %-7s  jitter %-7s  max %-7s  loss %-6s  link %-12s  sig %s\n" \
        "$name" "${avg:-?}ms" "${mdev:-?}ms" "${max:-?}ms" "${loss:-?}" \
        "${link:-?}" "${signal:-?}"
}

devs=()
for dev in $(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null \
             | awk -F: '$2=="wifi" && $3=="connected"{print $1}'); do
    devs+=("$dev")
done

if [ ${#devs[@]} -eq 0 ]; then
    echo "No connected WiFi adapter found."
    exit 1
fi

echo "Pinging $TARGET ($COUNT packets) over each connected adapter — lower avg & jitter is better:"
echo
for dev in "${devs[@]}"; do
    measure "$dev"
done

if [ ${#devs[@]} -eq 1 ]; then
    echo
    echo "Only one adapter is connected (failover keeps the other down)."
    echo "Plug/unplug the USB adapter and run this again to compare."
fi
