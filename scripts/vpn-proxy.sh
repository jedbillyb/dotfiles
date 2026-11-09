#!/bin/bash
# TCP-over-SSH fallback for networks that block UDP (so WireGuard can't handshake).
#
# Brings up an SSH SOCKS proxy and points all outbound TCP at it with redsocks,
# so it behaves like a VPN without needing UDP. DNS is left alone - it keeps
# using whatever the local network hands out, which is what works on such
# networks anyway.
#
# Three moving parts have to be live at once - the ssh listener, redsocks, and
# the nat redirect - and any one of them can go without the others noticing.
# That matters more here than in the other transports: vpn-toggle.sh caches
# whichever transport reported success and tries it first next time, so a false
# success pins the slowest transport on that network and the ladder never
# reaches the fast ones again. So 'up' proves the proxy actually carries
# traffic before returning, 'status' answers for all three legs rather than
# just ssh, and a detached watchdog undoes a half-built redirect if this script
# is killed between installing the rules and confirming them.
#
# Usage: vpn-proxy.sh up|down|status

set -uo pipefail

SELF="$(readlink -f "$0")"
SERVER_IP="152.69.172.139"
SSH_TARGET="ubuntu@${SERVER_IP}"
SOCKS_PORT=1080
REDSOCKS_PORT=12345
CHAIN="VPNPROXY"
RUNDIR="/tmp/vpn-proxy"
SSH_PID="${RUNDIR}/ssh.pid"
REDSOCKS_PID="${RUNDIR}/redsocks.pid"
REDSOCKS_CONF="${RUNDIR}/redsocks.conf"
OK_FLAG="${RUNDIR}/confirmed"
WD_PID="${RUNDIR}/watchdog.pid"

WATCHDOG_TIMEOUT=90

# All three legs, not just ssh. A live ssh listener with redsocks dead or the
# nat jump missing is not "up" - it is the exact half-state that used to report
# success and get cached as this network's working transport.
ssh_alive() {
    [[ -f "$SSH_PID" ]] && kill -0 "$(cat "$SSH_PID")" 2>/dev/null
}

redsocks_alive() {
    # redsocks runs as root, so an unprivileged kill -0 fails with EPERM even
    # when the process is there.
    [[ -f "$REDSOCKS_PID" ]] && sudo kill -0 "$(cat "$REDSOCKS_PID")" 2>/dev/null
}

rules_live() {
    sudo iptables -t nat -C OUTPUT -p tcp -j "$CHAIN" 2>/dev/null
}

is_up() {
    ssh_alive && redsocks_alive && rules_live
}

# redsocks only redirects IPv4 TCP, and the server has no IPv6 egress at all, so
# global IPv6 can never go through this tunnel. On a connection with native IPv6
# (Starlink) it would otherwise sail straight out and every v6-capable site would
# still see the real address. Fail closed instead. Link-local and ULA are left
# alone so NDP and DHCPv6 keep working.
v6_block_up() {
    sudo ip6tables -C OUTPUT -d 2000::/3 -j REJECT --reject-with adm-prohibited 2>/dev/null ||
        sudo ip6tables -I OUTPUT 1 -d 2000::/3 -j REJECT --reject-with adm-prohibited
}

v6_block_down() {
    while sudo ip6tables -D OUTPUT -d 2000::/3 -j REJECT --reject-with adm-prohibited 2>/dev/null; do :; done
}

# DNS stays local here by design, so this deliberately uses the system resolver
# rather than probing a public one the way the UDP transports do - on a network
# that blocks UDP, dig @1.1.1.1 would fail even when the proxy is perfect.
verify() {
    local ip_ok=no dns_ok=no name_ok=no egress=unknown
    timeout 8  curl -sS -o /dev/null --max-time 7 https://1.1.1.1 2>/dev/null && ip_ok=yes
    timeout 6  getent hosts github.com >/dev/null 2>&1 && dns_ok=yes
    timeout 10 curl -sS -o /dev/null --max-time 9 https://github.com 2>/dev/null && name_ok=yes

    # The only thing that actually proves the redirect is carrying traffic:
    # what the far end sees has to be the SSH server, not this network. With
    # the nat rules missing, every check above still passes - the traffic just
    # goes out in the clear. A blank or malformed answer proves nothing either
    # way, so it is not counted against us.
    local seen
    seen=$(timeout 10 curl -sS --max-time 9 https://ifconfig.me 2>/dev/null | tr -d '[:space:]')
    if [[ "$seen" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ "$seen" == "$SERVER_IP" ]]; then egress=ok; else egress="leak($seen)"; fi
    fi

    echo "ip=$ip_ok dns=$dns_ok name=$name_ok egress=$egress"
    [[ $ip_ok == yes && $dns_ok == yes && $name_ok == yes && $egress != leak* ]]
}

# Every outbound TCP connection on the machine goes through these rules, so a
# partially installed set is worse than none at all. Any failure aborts.
install_rules() {
    sudo iptables -t nat -N "$CHAIN" 2>/dev/null
    sudo iptables -t nat -F "$CHAIN" || return 1

    # Anything local, private, or the SSH server itself must go out directly -
    # redirecting the SSH connection into its own proxy would deadlock.
    local net
    for net in 0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 \
               172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4 \
               "${SERVER_IP}/32"; do
        sudo iptables -t nat -A "$CHAIN" -d "$net" -j RETURN || return 1
    done

    sudo iptables -t nat -A "$CHAIN" -p tcp -j REDIRECT --to-ports "$REDSOCKS_PORT" || return 1
    sudo iptables -t nat -A OUTPUT -p tcp -j "$CHAIN" || return 1
    v6_block_up || return 1
}

teardown_rules() {
    # Detach the chain first so no new traffic hits it, then flush and drop it.
    while sudo iptables -t nat -D OUTPUT -p tcp -j "$CHAIN" 2>/dev/null; do :; done
    sudo iptables -t nat -F "$CHAIN" 2>/dev/null
    sudo iptables -t nat -X "$CHAIN" 2>/dev/null
    v6_block_down
}

# Armed before the nat rules go in, so being killed mid-build cannot strand
# every TCP connection on the machine pointing at a redsocks that isn't there.
start_watchdog() {
    stop_watchdog
    setsid bash -c "
        sleep $WATCHDOG_TIMEOUT
        [[ -f '$OK_FLAG' ]] && exit 0
        logger -t vpn-proxy 'watchdog fired: proxy unconfirmed, tearing down'
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
    # RUNDIR lives in /tmp, so a reboot or a tmp sweep can take the pidfile
    # while the ssh client itself survives. Without this the orphan keeps
    # port 1080 and every later start fails to bind.
    pkill -f -- "-D 127.0.0.1:${SOCKS_PORT} ${SSH_TARGET}" 2>/dev/null

    rm -f "$REDSOCKS_CONF" "$OK_FLAG"
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
    rm -f "$OK_FLAG"
    start_watchdog

    ssh -o BatchMode=yes \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=4 \
        -o StrictHostKeyChecking=accept-new \
        -N -D "127.0.0.1:${SOCKS_PORT}" "$SSH_TARGET" >/dev/null 2>&1 &
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
        echo "ssh socks proxy failed to come up" >&2
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
        echo "redsocks failed to start" >&2
        down
        return 1
    fi

    if ! install_rules; then
        echo "failed to install nat redirect" >&2
        down
        return 1
    fi

    # Everything is running. That is not the same as traffic reaching the far
    # end through it, so prove that before reporting success.
    local result
    for _ in $(seq 1 6); do
        result=$(verify) && { echo "$result"; touch "$OK_FLAG"; stop_watchdog; return 0; }
        sleep 2
    done

    echo "proxy up but unusable ($result)" >&2
    down
    return 1
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
