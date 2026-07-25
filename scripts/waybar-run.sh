#!/bin/sh
# Supervise waybar: keep it running, and bring it back if it dies.
#
# Started from sway's `exec_always`, which fires again on every config reload,
# so this has to be safe to invoke repeatedly -- a second copy would mean two
# supervisors racing to respawn one bar.
#
# Mod+b (`pkill -SIGUSR1 waybar`) only toggles waybar's *visibility*; the
# process keeps running. So supervising on process death does not fight the
# hide toggle: a hidden bar is still very much alive.

set -u

WAYBAR=${WAYBAR:-waybar}

# Everything below is scoped per Wayland display. More than one sway session
# can be running (a second compositor on another tty is easy to end up with),
# and a shared lock plus a machine-wide `pkill -x waybar` makes them fight:
# one session's reload kills the other session's bar, and whichever supervisor
# loses the lock exits.
DISPLAY_ID=$(printf '%s' "${WAYLAND_DISPLAY:-nodisplay}" | tr -c 'A-Za-z0-9_-' '_')
LOCKFILE=/tmp/waybar-run.$(id -u).$DISPLAY_ID.lock
PIDFILE=/tmp/waybar-run.$(id -u).$DISPLAY_ID.pid
# Set by a reload handover just before it kills the bar, so the supervisor can
# tell "sway reloaded" from "waybar fell over" -- otherwise a few reloads in
# quick succession look like a crash loop and the bar comes back slower each
# time.
RESTART_FLAG=/tmp/waybar-run.$(id -u).$DISPLAY_ID.restart

# Small breadcrumb log. The supervisor is started by sway and has no terminal,
# so without this there is no way to see why it stopped.
LOGFILE=${XDG_CACHE_HOME:-$HOME/.cache}/waybar-run.log
log() {
	mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
	printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "$$" "$*" >>"$LOGFILE" 2>/dev/null || true
}

# Restarts closer together than this are treated as a crash loop rather than
# an ordinary respawn.
CRASH_WINDOW=5
# Backoff bounds for that loop, so a broken config cannot spin the CPU.
MIN_DELAY=1
MAX_DELAY=30

# Stop only the bar belonging to this display, by the pid the supervisor
# recorded. Deliberately not `pkill -x waybar`, which would also take out the
# bar of any other sway session running on the machine.
kill_our_bar() {
	[ -f "$PIDFILE" ] || return 0
	_p=$(cat "$PIDFILE" 2>/dev/null)
	case "$_p" in
	'' | *[!0-9]*) rm -f "$PIDFILE"; return 0 ;;
	esac
	# Confirm it really is a waybar before signalling: pids get reused.
	if [ "$(cat "/proc/$_p/comm" 2>/dev/null)" = "waybar" ]; then
		kill "$_p" 2>/dev/null || true
	fi
	rm -f "$PIDFILE"
}

exec 9>"$LOCKFILE"
if ! flock -n 9; then
	# A supervisor is already running. This is a sway reload, so just drop the
	# current bar -- the existing supervisor respawns it and picks up any
	# changed waybar config. Flag it first so that respawn is immediate rather
	# than treated as a crash and backed off.
	log "reload handover: another supervisor holds the lock, restarting its bar"
	: >"$RESTART_FLAG" 2>/dev/null || true
	kill_our_bar
	exit 0
fi

# Inherited from a previous session (or a hand-started bar): adopt it rather
# than leaving an unsupervised copy behind. Any flag left by a dead supervisor
# is stale.
log "supervisor starting (took the lock) on $DISPLAY_ID"
rm -f "$RESTART_FLAG"
# Left over from a supervisor that died without cleaning up.
kill_our_bar

cleanup() {
	log "supervisor exiting on signal; taking the bar down with it"
	# Don't leave the bar behind when the supervisor goes down with the session.
	rm -f "$RESTART_FLAG"
	kill_our_bar
	exit 0
}
trap cleanup INT TERM HUP

delay=$MIN_DELAY
while :; do
	start=$(date +%s)
	log "starting waybar"
	"$WAYBAR" >/dev/null 2>&1 &
	bar=$!
	printf '%s\n' "$bar" >"$PIDFILE" 2>/dev/null || true
	wait "$bar"
	status=$?
	rm -f "$PIDFILE"
	end=$(date +%s)
	log "waybar exited status=$status after $((end - start))s"

	# Deliberately no special case for a zero exit status. waybar exits 0 when
	# it is SIGTERMed, which is exactly what the reload handover above does --
	# so treating a clean exit as "stop" made every second sway reload kill the
	# bar and leave it dead until the next reload. There is no way to tell a
	# deliberate quit from the handover here, and a supervisor that stops
	# supervising is the worse failure. To stop the bar, stop the supervisor.
	# A reload asked for this restart, so come straight back and forget any
	# accumulated backoff.
	if [ -e "$RESTART_FLAG" ]; then
		log "that was a reload handover; restarting immediately"
		rm -f "$RESTART_FLAG"
		delay=$MIN_DELAY
		continue
	fi

	if [ $((end - start)) -lt "$CRASH_WINDOW" ]; then
		# Died immediately -- almost certainly a broken config or a missing
		# module binary. Back off so this degrades into a slow retry rather
		# than a hot loop.
		printf 'waybar-run: waybar exited (%s) after %ss, retrying in %ss\n' \
			"$status" "$((end - start))" "$delay" >&2
		sleep "$delay"
		delay=$((delay * 2))
		[ "$delay" -gt "$MAX_DELAY" ] && delay=$MAX_DELAY
	else
		# Ran for a while, so this is a genuine crash: come back promptly and
		# reset the backoff.
		delay=$MIN_DELAY
		sleep "$MIN_DELAY"
	fi
done
