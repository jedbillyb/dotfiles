#!/bin/bash
# TCP-over-SSH fallback for networks that block UDP (so WireGuard can't handshake).
#
# Brings up an SSH SOCKS proxy and points all outbound TCP at it with redsocks,
# so it behaves like a VPN without needing UDP. DNS is left alone - it keeps
# using whatever the local network hands out, which is what works on such
# networks anyway.
#
# Usage: vpn-proxy.sh up|down|status

set -uo pipefail

SERVER_IP="152.69.172.139"
SSH_TARGET="ubuntu@${SERVER_IP}"
SOCKS_PORT=1080
REDSOCKS_PORT=12345
CHAIN="VPNPROXY"
RUNDIR="/tmp/vpn-proxy"
SSH_PID="${RUNDIR}/ssh.pid"
REDSOCKS_PID="${RUNDIR}/redsocks.pid"
REDSOCKS_CONF="${RUNDIR}/redsocks.conf"

is_up() {
    [[ -f "$SSH_PID" ]] && kill -0 "$(cat "$SSH_PID")" 2>/dev/null
}

teardown_rules() {
    # Detach the chain first so no new traffic hits it, then flush and drop it.
    while sudo iptables -t nat -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null; do :; done
    sudo iptables -t nat -F "$CHAIN" 2>/dev/null
    sudo iptables -t nat -X "$CHAIN" 2>/dev/null
}

down() {
    teardown_rules

    # redsocks runs as root, so killing it needs sudo; the ssh client doesn't.
    if [[ -f "$REDSOCKS_PID" ]]; then
        sudo kill "$(cat "$REDSOCKS_PID")" 2>/dev/null
        rm -f "$REDSOCKS_PID"
    fi
    # Catch any redsocks left behind by an earlier crash - it would hold the
    # port and stop the next start.
    sudo pkill -f "redsocks -c ${REDSOCKS_CONF}" 2>/dev/null

    if [[ -f "$SSH_PID" ]]; then
        pid=$(cat "$SSH_PID")
        kill "$pid" 2>/dev/null
        for _ in $(seq 1 20); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$pid" 2>/dev/null
        rm -f "$SSH_PID"
    fi

    rm -f "$REDSOCKS_CONF"
    rmdir "$RUNDIR" 2>/dev/null
    return 0
}

up() {
    if is_up; then
        echo "already up"
        return 0
    fi

    # Any half-dead state from a previous run would otherwise strand traffic.
    down

    mkdir -p "$RUNDIR"

    ssh -o BatchMode=yes \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=4 \
        -o StrictHostKeyChecking=accept-new \
        -N -D "127.0.0.1:${SOCKS_PORT}" "$SSH_TARGET" &
    echo $! > "$SSH_PID"

    # SSH setup on restrictive networks can be slow and erratic, so poll for the
    # listener rather than assuming a fixed delay.
    local ready=0
    for _ in $(seq 1 60); do
        if ! kill -0 "$(cat "$SSH_PID")" 2>/dev/null; then
            break
        fi
        if (exec 3<>/dev/tcp/127.0.0.1/${SOCKS_PORT}) 2>/dev/null; then
            ready=1
            break
        fi
        sleep 0.5
    done

    if [[ $ready -ne 1 ]]; then
        echo "ssh socks proxy failed to come up"
        down
        return 1
    fi

    cat > "$REDSOCKS_CONF" <<EOF
base {
    log_debug = off;
    log_info = off;
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = ${REDSOCKS_PORT};
    ip = 127.0.0.1;
    port = ${SOCKS_PORT};
    type = socks5;
}
EOF

    if ! sudo redsocks -c "$REDSOCKS_CONF" -p "$REDSOCKS_PID" 2>/dev/null; then
        echo "redsocks failed to start"
        down
        return 1
    fi

    sudo iptables -t nat -N "$CHAIN" 2>/dev/null
    sudo iptables -t nat -F "$CHAIN"

    # Anything local, private, or the SSH server itself must go out directly -
    # redirecting the SSH connection into its own proxy would deadlock.
    for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 \
               172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 \
               "${SERVER_IP}/32"; do
        sudo iptables -t nat -A "$CHAIN" -d "$net" -j RETURN
    done

    sudo iptables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$REDSOCKS_PORT"
    sudo iptables -t nat -A OUTPUT -p tcp -j "$CHAIN"

    echo "up"
    return 0
}

status() {
    if is_up; then
        echo "up"
        return 0
    fi
    echo "down"
    return 1
}

case "${1:-}" in
    up)     up ;;
    down)   down ;;
    status) status ;;
    *)      echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
