#!/bin/bash
# Waybar custom network module: signal % + up/down throughput for the ACTIVE
# wifi adapter (whichever holds the default route). Fields are padded to a fixed
# width so the bar never reflows AND there is no wasted blank space.
# Throughput is in bits/s to match the old built-in display.

state_dir="${XDG_RUNTIME_DIR:-/tmp}"

iface="$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')"

if [ -z "$iface" ] || [ ! -d "/sys/class/net/$iface/wireless" ]; then
    echo '{"text":"wifi off","class":"disconnected"}'
    exit 0
fi

# signal % of the active AP
sig="$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')"
[ -z "$sig" ] && sig="?"

rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null)
tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null)
now=$(date +%s.%N)

f="$state_dir/netspeed.$iface"
pnow=0; prx=0; ptx=0
[ -f "$f" ] && read -r pnow prx ptx < "$f"
echo "$now $rx $tx" > "$f"

drx=0; dtx=0
if awk "BEGIN{dt=$now-$pnow; exit !(dt>0 && dt<60)}"; then
    drx=$(awk "BEGIN{printf \"%.0f\", ($rx-$prx)*8/($now-$pnow)}")
    dtx=$(awk "BEGIN{printf \"%.0f\", ($tx-$ptx)*8/($now-$pnow)}")
fi

# bits/s -> fixed 5-char field, e.g. "   0b" "274k" "1.2M"
human() {
    awk -v v="$1" 'BEGIN{
        split("b k M G", u, " ");
        i=1;
        while (v>=1000 && i<4){v/=1000; i++}
        if (i==1 || v>=100) fmt=sprintf("%d%s", v, u[i]);
        else                fmt=sprintf("%.1f%s", v, u[i]);
        printf "%5s", fmt;
    }'
}

printf '{"text":"wifi %3s%% ↓%s ↑%s","class":"connected"}\n' \
    "$sig" "$(human "$drx")" "$(human "$dtx")"
