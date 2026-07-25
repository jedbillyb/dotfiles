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
LOCKFILE=/tmp/waybar-run.$(id -u).lock

# Restarts closer together than this are treated as a crash loop rather than
# an ordinary respawn.
CRASH_WINDOW=5
# Backoff bounds for that loop, so a broken config cannot spin the CPU.
MIN_DELAY=1
MAX_DELAY=30

exec 9>"$LOCKFILE"
if ! flock -n 9; then
	# A supervisor is already running. This is a sway reload, so just drop the
	# current bar -- the existing supervisor respawns it and picks up any
	# changed waybar config.
	pkill -x waybar 2>/dev/null || true
	exit 0
fi

# Inherited from a previous session (or a hand-started bar): adopt it rather
# than leaving an unsupervised copy behind.
pkill -x waybar 2>/dev/null || true

cleanup() {
	# Don't leave the bar behind when the supervisor goes down with the session.
	pkill -x waybar 2>/dev/null || true
	exit 0
}
trap cleanup INT TERM HUP

delay=$MIN_DELAY
while :; do
	start=$(date +%s)
	"$WAYBAR" >/dev/null 2>&1
	status=$?
	end=$(date +%s)

	# A clean exit means something asked waybar to quit; respect that instead
	# of fighting it.
	if [ "$status" -eq 0 ]; then
		exit 0
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
