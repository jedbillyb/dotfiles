#!/bin/bash
# Full-tunnel WireGuard over TCP/443, for networks that block or filter UDP.
#
# Unlike vpn-proxy.sh (SSH SOCKS + redsocks) this is a real VPN: actual
# WireGuard runs inside a WebSocket, so UDP and DNS go through it too, not just
# IPv4 TCP. The server side is wstunnel behind nginx on server.jedbillyb.com,
# reached on a secret path that doubles as the shared secret.
#
# A completed handshake is NOT proof the tunnel is usable - it can hand back a
# link that passes ICMP but resolves nothing. So 'up' only keeps the tunnel if
# it independently confirms DNS and HTTPS through it, and a detached watchdog
# tears everything down if that confirmation never arrives.
#
# Usage: vpn-wstunnel.sh up|down|status|diag

set -uo pipefail

SELF="$(readlink -f "$0")"
ENV_FILE="/etc/wstunnel/client.env"
# Absolute: the sway session PATH does not reliably include /usr/local/bin.
WSTUNNEL_BIN="/usr/local/bin/wstunnel"
WG_IF="wg-tcp"
RUNDIR="/tmp/vpn-wstunnel"
WST_PID="${RUNDIR}/wstunnel.pid"
WST_LOG="${RUNDIR}/wstunnel.log"
# For the waybar module, which runs unprivileged. The wireguard peer here is
# only 127.0.0.1 - the interesting remote is the wstunnel server, so that is
# what gets recorded. See waybar/vpn-status.sh.
FACTS_DIR="${XDG_RUNTIME_DIR:-/tmp}/vpn-facts"
FACTS="${FACTS_DIR}/${WG_IF}.facts"
DIAG_LOG="${RUNDIR}/diagnostics.log"
OK_FLAG="${RUNDIR}/confirmed"
WD_PID="${RUNDIR}/watchdog.pid"

HANDSHAKE_TIMEOUT=15
WATCHDOG_TIMEOUT=45

# The path prefix is a credential, so the env file is root:wheel 0640 - readable
# without sudo by us, unreadable by anyone else. Keeping it out of sudo means the
# NOPASSWD rule below stays narrow instead of needing blanket grep/test as root.
load_env() {
    if [[ ! -r "$ENV_FILE" ]]; then
        echo "cannot read $ENV_FILE" >&2
        return 1
    fi
    eval "$(grep -E '^(WST_HOST|WST_PATH|WST_LOCAL_PORT|WST_SERVER_IP)=' "$ENV_FILE")"
}

wst_running() { [[ -f "$WST_PID" ]] && kill -0 "$(cat "$WST_PID")" 2>/dev/null; }
wg_up()       { ip link show "$WG_IF" &>/dev/null; }

handshaked() {
    local hs
    hs=$(sudo /usr/bin/wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
    [[ -n "$hs" && "$hs" != "0" ]]
}

# wstunnel's own connection to the server must never enter the tunnel it
# carries, or it deadlocks. wg-tcp.conf installs this too, but doing it up
# front removes the window where an established connection would break.
pin_route() {
    local gw dev
    gw=$(ip route show default | awk '{print $3; exit}')
    dev=$(ip route show default | awk '{print $5; exit}')
    [[ -n "$gw" && -n "$dev" ]] || return 1
    sudo /usr/bin/ip route replace "${WST_SERVER_IP}/32" via "$gw" dev "$dev"
}

unpin_route() { sudo /usr/bin/ip route del "${WST_SERVER_IP}/32" 2>/dev/null; }

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
        echo "--- wg ---";        sudo /usr/bin/wg show "$WG_IF" 2>&1 | grep -v 'private key'
        echo "--- routes ---";    ip route
        echo "--- rules ---";     ip -4 rule
        echo "--- resolv ---";    cat /etc/resolv.conf
        echo "--- mtu probe (through tunnel) ---"
        for sz in 1200 1400 1500; do
            if ping -c1 -W2 -M do -s $((sz - 28)) 1.1.1.1 >/dev/null 2>&1; then
                echo "  ${sz}B OK"
            else
                echo "  ${sz}B FAIL"
            fi
        done
        echo "--- verify ---";    verify
        echo "--- wstunnel log tail ---"; tail -20 "$WST_LOG" 2>/dev/null
    } >>"$DIAG_LOG" 2>&1
}

# Detached so it outlives this shell, the terminal, and any parent that dies
# mid-run. If 'up' never confirms, this is what saves the session.
start_watchdog() {
    stop_watchdog
    setsid bash -c "
        sleep $WATCHDOG_TIMEOUT
        [[ -f '$OK_FLAG' ]] && exit 0
        logger -t vpn-wstunnel 'watchdog fired: tunnel unconfirmed, tearing down'
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
    load_env || return 1
    stop_watchdog
    wg_up && sudo /usr/bin/wg-quick down "$WG_IF" >/dev/null 2>&1
    rm -f "$FACTS"
    if [[ -f "$WST_PID" ]]; then
        kill "$(cat "$WST_PID")" 2>/dev/null
        rm -f "$WST_PID"
    fi
    # Catch anything left behind by an earlier crash; it would hold the port.
    pkill -f 'wstunnel client' 2>/dev/null
    unpin_route
    rm -f "$OK_FLAG"
}

up() {
    load_env || return 1
    mkdir -p "$RUNDIR"
    rm -f "$OK_FLAG"

    if ! pin_route; then
        echo "no default route to pin against" >&2
        return 1
    fi

    # Armed before anything captures the default route, so every failure path
    # below - including an unexpected hang - still gets undone.
    start_watchdog

    "$WSTUNNEL_BIN" client \
        -L "udp://${WST_LOCAL_PORT}:127.0.0.1:51820?timeout_sec=0" \
        -P "$WST_PATH" \
        "wss://${WST_HOST}:443" >"$WST_LOG" 2>&1 &
    echo $! > "$WST_PID"

    # Wait for the local UDP listener before handing WireGuard an endpoint that
    # would otherwise refuse instantly.
    local ready=no
    for _ in $(seq 1 20); do
        if ss -ulnH "sport = :${WST_LOCAL_PORT}" | grep -q .; then ready=yes; break; fi
        wst_running || break
        sleep 0.25
    done
    if [[ $ready != yes ]]; then
        echo "wstunnel failed to start; see $WST_LOG" >&2
        down
        return 1
    fi

    if ! sudo /usr/bin/wg-quick up "$WG_IF" >/dev/null 2>&1; then
        echo "wg-quick up $WG_IF failed" >&2
        down
        return 1
    fi

    local got=no
    for _ in $(seq 1 $((HANDSHAKE_TIMEOUT * 2))); do
        handshaked && { got=yes; break; }
        sleep 0.5
    done

    mkdir -p "$FACTS_DIR"
    printf 'endpoint=%s:443\n' "$WST_HOST" > "$FACTS"

    if [[ $got != yes ]]; then
        echo "no handshake over wstunnel; see $WST_LOG" >&2
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
    status) load_env || exit 1; wg_up && wst_running && handshaked ;;
    diag)   cat "$DIAG_LOG" 2>/dev/null || echo "no diagnostics recorded" ;;
    *)      echo "usage: $0 up|down|status|diag" >&2; exit 2 ;;
esac
