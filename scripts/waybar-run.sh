#!/bin/sh
# Supervise waybar: keep it running, and bring it back if it dies.
#
# Started from sway's `exec_always`, which fires again on every config reload,
# so this has to be safe to invoke repeatedly -- a second copy would mean two
# supervisors racing to respawn one bar.
#
# Mod+b (waybar-toggle.sh) only toggles waybar's *visibility* while the bar is
# alive; the process keeps running. So supervising on process death does not
# fight the hide toggle: a hidden bar is still very much alive. When there is
# no bar to toggle, that script sends this supervisor SIGUSR1 to skip the
# restart backoff and respawn immediately.

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
# Where this supervisor announces itself, so waybar-toggle.sh can find it and
# poke it awake instead of starting a rival bar behind its back.
SUPERVISOR_PIDFILE=/tmp/waybar-run.$(id -u).$DISPLAY_ID.supervisor.pid

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

# Every waybar belonging to this display, including ones this supervisor never
# started -- a bar orphaned by a supervisor that died, or one launched by hand.
# The pidfile alone is not enough: a stray has no entry in it. Scoped by
# reading each process's own WAYLAND_DISPLAY, so other sessions are left alone.
bars_here() {
	for _pid in $(pgrep -x waybar 2>/dev/null); do
		_d=$(tr '\0' '\n' < "/proc/$_pid/environ" 2>/dev/null |
			sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1)
		[ "$_d" = "${WAYLAND_DISPLAY:-}" ] && printf '%s\n' "$_pid"
	done
	return 0
}

# Sweep the display, so we never end up running a second bar alongside one that
# is already there.
kill_stray_bars() {
	for _pid in $(bars_here); do
		kill "$_pid" 2>/dev/null || true
	done
}

# Is there really a supervisor behind the lock? The lock alone does not prove
# it: fd 9 is inherited by everything the supervisor spawns, so a waybar module
# script that outlives its bar goes on holding the lock forever with nobody
# supervising anything. (`waybar` is now started with fd 9 closed, which stops
# that happening again, but a session that started before that fix can still be
# in this state.) Pid reuse is checked by looking for our own name in cmdline.
supervisor_alive() {
	_s=$(cat "$SUPERVISOR_PIDFILE" 2>/dev/null) || return 1
	case "$_s" in
	'' | *[!0-9]*) return 1 ;;
	esac
	# Subshell: a missing /proc entry is the shell's own redirect error, which
	# a redirection on the command itself would not silence.
	(tr '\0' ' ' < "/proc/$_s/cmdline") 2>/dev/null | grep -q 'waybar-run'
}

exec 9>"$LOCKFILE"
if ! flock -n 9; then
	# A supervisor is already running -- or one from before this script wrote a
	# supervisor pidfile is, in which case its bar is the giveaway. Either way
	# this is a sway reload, so just drop the current bar: the existing
	# supervisor respawns it and picks up any changed waybar config. Flag it
	# first so that respawn is immediate rather than treated as a crash and
	# backed off.
	if supervisor_alive || [ -n "$(bars_here)" ]; then
		log "reload handover: another supervisor holds the lock, restarting its bar"
		: >"$RESTART_FLAG" 2>/dev/null || true
		kill_our_bar
		exit 0
	fi

	# Locked, but no supervisor and no bar: the holder is an orphan clinging to
	# an inherited fd. Left alone this wedges the bar permanently -- every
	# attempt to start it, on reload or by hand, mistakes the orphan for a live
	# supervisor and bows out. Unlink the lockfile and make a new one: the
	# orphan keeps its lock on the now-nameless inode, where it bothers nobody.
	log "stale lock with no supervisor and no bar; breaking it"
	rm -f "$LOCKFILE"
	exec 9>"$LOCKFILE"
	if ! flock -n 9; then
		log "could not take the replacement lock; giving up"
		exit 1
	fi
fi

# Inherited from a previous session (or a hand-started bar): adopt it rather
# than leaving an unsupervised copy behind. Any flag left by a dead supervisor
# is stale.
log "supervisor starting (took the lock) on $DISPLAY_ID"
rm -f "$RESTART_FLAG"
# Left over from a supervisor that died without cleaning up, or started by
# hand. Sweep the display so we never end up running a second bar alongside
# one that is already there.
kill_stray_bars
rm -f "$PIDFILE"
printf '%s\n' "$$" >"$SUPERVISOR_PIDFILE" 2>/dev/null || true

cleanup() {
	log "supervisor exiting on signal; taking the bar down with it"
	# Don't leave the bar behind when the supervisor goes down with the session.
	rm -f "$RESTART_FLAG" "$SUPERVISOR_PIDFILE"
	kill_our_bar
	exit 0
}
trap cleanup INT TERM HUP

# Mod+b pressed while no bar is on screen. Only meaningful during the restart
# backoff below; at any other moment the bar is already up (or about to be) and
# this just means "don't dawdle".
kicked=0
trap 'kicked=1; log "kick received; restarting waybar now"' USR1

# `sleep` as a plain foreground command would swallow the kick: the shell only
# runs a trap once the current command finishes, so a 30s backoff would stay a
# 30s wait. Waiting on a *background* sleep uses the `wait` builtin, which the
# signal does interrupt.
nap() {
	sleep "$1" 9>&- &
	_nap=$!
	wait "$_nap" 2>/dev/null
	kill "$_nap" 2>/dev/null || true
}

delay=$MIN_DELAY
while :; do
	kicked=0
	start=$(date +%s)
	log "starting waybar"
	# 9>&- keeps the lock fd out of the bar and, more to the point, out of the
	# module scripts it spawns: one of those outliving its bar while still
	# holding the lock is what used to strand the bar with no way back.
	"$WAYBAR" >/dev/null 2>&1 9>&- &
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
		nap "$delay"
		delay=$((delay * 2))
		[ "$delay" -gt "$MAX_DELAY" ] && delay=$MAX_DELAY
	else
		# Ran for a while, so this is a genuine crash: come back promptly and
		# reset the backoff.
		delay=$MIN_DELAY
		nap "$MIN_DELAY"
	fi

	# Asked for by hand mid-backoff: come back at full speed, and drop the
	# accumulated delay so a user-driven retry is never the slow path.
	if [ "$kicked" = 1 ]; then
		delay=$MIN_DELAY
	fi
done
