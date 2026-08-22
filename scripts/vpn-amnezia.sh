#!/bin/bash
# Full-tunnel AmneziaWG over UDP/123, for networks that inspect UDP by port and
# fingerprint the WireGuard handshake.
#
# This is real WireGuard - AmneziaWG only changes the four message-type bytes -
# so it keeps kernel-grade behaviour with none of the TCP-over-TCP penalty that
# vpn-wstunnel.sh pays. Measured on the N4L school wifi: 125 Mbit/s, 0% loss.
#
# Why it works there, from packet-level testing on 2026-08-19/20:
#   - That network caps unclassified UDP flows at ~4 packets, but UDP/123 (NTP)
#     is exempt and sustains traffic indefinitely.
#   - UDP/123 inspects the first byte and only passes plausible NTP modes.
#     WireGuard's message types 1-4 happen to be valid NTP modes, so they pass.
#   - A stateful DPI drops the pair "148B type-1 out, 92B type-2 back". Changing
#     the type bytes (H1-H4) breaks the match and the handshake completes.
# Hence Jc/S1/S2 MUST stay 0: junk and junk-prefixes put random leading bytes on
# the wire, which the NTP first-byte inspector drops.
#
# A completed handshake is NOT proof the tunnel is usable - twice during
# development it handshook while forwarding was silently rejected server-side.
# So 'up' only keeps the tunnel if it independently confirms DNS and HTTPS
# through it, and a detached watchdog tears everything down otherwise.
#
# Usage: vpn-amnezia.sh up|down|status|diag

set -uo pipefail

SELF="$(readlink -f "$0")"
AWG_IF="awg0"
# Absolute: the sway session PATH does not reliably include /usr/local/bin.
AWG_QUICK="/usr/bin/awg-quick"
AWG="/usr/bin/awg"
RUNDIR="/tmp/vpn-amnezia"
DIAG_LOG="${RUNDIR}/diagnostics.log"
OK_FLAG="${RUNDIR}/confirmed"
WD_PID="${RUNDIR}/watchdog.pid"
# What we actually dialled, left where the unprivileged waybar module can read
# it. `awg show` needs root and waybar has none, so the tooltip would otherwise
# have to hardcode an endpoint and quietly go stale the day it changes.
FACTS_DIR="${XDG_RUNTIME_DIR:-/tmp}/vpn-facts"
FACTS="${FACTS_DIR}/${AWG_IF}.facts"

HANDSHAKE_TIMEOUT=15
WATCHDOG_TIMEOUT=45

awg_up() { ip link show "$AWG_IF" &>/dev/null; }

handshaked() {
    local hs
    hs=$(sudo "$AWG" show "$AWG_IF" latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
    [[ -n "$hs" && "$hs" != "0" ]]
}

# Check each layer separately so a failure says which one broke, rather than
# just "no internet". Deliberately avoids the system resolver for the IP test.
verify() {
    local ip_ok=no dns_ok=no name_ok=no
    timeout 8  curl -sS -o /dev/null --max-time 7 https://1.1.1.1 2>/dev/null && ip_ok=yes
    timeout 6  dig +time=2 +tries=1 @1.1.1.1 cloudflare.com +short >/dev/null 2>&1 && dns_ok=yes
    timeout 10 curl -sS -o /dev/null --max-time 9 https://github.com 2>/dev/null && name_ok=yes
    echo "ip=$ip_ok dns=$dns_ok name=$name_ok"
    [[ $ip_ok == yes && $dns_ok == yes && $name_ok == yes ]]
}

# Snapshot enough state to debug a failure after the tunnel is already gone.
capture_diag() {
    {
        echo "===== $(date -Is) ====="
        echo "--- awg ---";     sudo "$AWG" show "$AWG_IF" 2>&1 | grep -v 'private key'
        echo "--- routes ---";  ip route
        echo "--- rules ---";   ip -4 rule
        echo "--- resolv ---";  cat /etc/resolv.conf
        echo "--- mtu probe (through tunnel) ---"
        for sz in 1200 1400 1500; do
            printf '  %s: ' "$sz"
            ping -c1 -W2 -M do -s $((sz - 28)) 1.1.1.1 >/dev/null 2>&1 && echo ok || echo fail
        done
        echo "--- verify ---";  verify
    } >>"$DIAG_LOG" 2>&1
}

# Detached so it outlives this shell, the terminal, and any parent that dies
# mid-run. If 'up' never confirms, this is what saves the session.
start_watchdog() {
    stop_watchdog
    setsid bash -c "
        sleep $WATCHDOG_TIMEOUT
        [[ -f '$OK_FLAG' ]] && exit 0
        logger -t vpn-amnezia 'watchdog fired: tunnel unconfirmed, tearing down'
        '$SELF' down >/dev/null 2>&1
    " >/dev/null 2>&1 &
    echo $! > "$WD_PID"
    disown 2>/dev/null || true
}

stop_watchdog() {
    if [[ -f "$WD_PID" ]]; then
        kill -- "-$(cat "$WD_PID")" 2>/dev/null
        kill "$(cat "$WD_PID")" 2>/dev/null
        rm -f "$WD_PID"
    fi
}

down() {
    stop_watchdog
    awg_up && sudo "$AWG_QUICK" down "$AWG_IF" >/dev/null 2>&1
    rm -f "$OK_FLAG" "$FACTS"
}

up() {
    mkdir -p "$RUNDIR"
    rm -f "$OK_FLAG"

    # Armed before anything captures the default route, so every failure path
    # below - including an unexpected hang - still gets undone.
    start_watchdog

    if ! sudo "$AWG_QUICK" up "$AWG_IF" >/dev/null 2>&1; then
        echo "awg-quick up $AWG_IF failed" >&2
        down
        return 1
    fi

    local got=no
    for _ in $(seq 1 $((HANDSHAKE_TIMEOUT * 2))); do
        handshaked && { got=yes; break; }
        sleep 0.5
    done

    # Written after the handshake, so it records an endpoint that is known to
    # answer rather than one that was merely configured.
    mkdir -p "$FACTS_DIR"
    sudo "$AWG" show "$AWG_IF" endpoints 2>/dev/null \
        | awk 'NF > 1 { print "endpoint=" $2; exit }' > "$FACTS"
    if [[ $got != yes ]]; then
        echo "no handshake on UDP/123" >&2
        capture_diag
        down
        return 1
    fi

    # The handshake means the transport works. It says nothing about whether
    # the tunnel is actually usable, so prove that before trusting it.
    local result
    for _ in $(seq 1 6); do
        result=$(verify) && { echo "$result"; touch "$OK_FLAG"; stop_watchdog; return 0; }
        sleep 2
    done

    echo "tunnel up but unusable ($result)" >&2
    capture_diag
    down
    return 1
}

case "${1:-}" in
    up)     up ;;
    down)   down ;;
    status) awg_up && handshaked ;;
    diag)   cat "$DIAG_LOG" 2>/dev/null || echo "no diagnostics recorded" ;;
    *)      echo "usage: $0 up|down|status|diag" >&2; exit 2 ;;
esac
