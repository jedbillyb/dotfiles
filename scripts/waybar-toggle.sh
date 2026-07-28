#!/bin/sh
# Mod+b: hide/show waybar -- and if it is not on screen at all, bring it back.
#
# waybar's own toggle is SIGUSR1, which only works on a live process. When the
# bar has crashed (or its supervisor has gone down with it) that signal lands
# nowhere and Mod+b silently does nothing, which reads as "the toggle is
# broken". So: signal the bar if there is one, otherwise restart it. Either
# way the keypress ends with a visible bar.

set -u

# Everything is scoped per Wayland display, matching waybar-run.sh: a second
# sway session on another tty has its own bar, supervisor and lock, and this
# must not reach across into it.
DISPLAY_ID=$(printf '%s' "${WAYLAND_DISPLAY:-nodisplay}" | tr -c 'A-Za-z0-9_-' '_')
SUPERVISOR_PIDFILE=/tmp/waybar-run.$(id -u).$DISPLAY_ID.supervisor.pid
RUNNER=${RUNNER:-$HOME/.local/bin/waybar-run.sh}

# Waybars belonging to this display, read from each process's own environment
# rather than a pidfile, so a bar the supervisor never started still counts.
bars_here() {
	for _pid in $(pgrep -x waybar 2>/dev/null); do
		_d=$(tr '\0' '\n' < "/proc/$_pid/environ" 2>/dev/null |
			sed -n 's/^WAYLAND_DISPLAY=//p' | head -n 1)
		[ "$_d" = "${WAYLAND_DISPLAY:-}" ] && printf '%s\n' "$_pid"
	done
}

bars=$(bars_here)
if [ -n "$bars" ]; then
	# Normal case: the bar is alive, so this is an ordinary hide/show.
	# shellcheck disable=SC2086 # deliberate word splitting: one signal per pid
	kill -USR1 $bars 2>/dev/null || true
	exit 0
fi

# No bar. If the supervisor is still up it is sitting in its restart backoff,
# which can be up to 30s away -- too slow to feel like a keypress did anything.
# SIGUSR1 tells it to stop waiting and respawn now. Going through the
# supervisor rather than launching waybar here matters: a bar started behind
# its back would be unsupervised, and would end up racing the respawn the
# supervisor was already about to do.
sup=$(cat "$SUPERVISOR_PIDFILE" 2>/dev/null || true)
case "$sup" in
'' | *[!0-9]*) sup='' ;;
esac
# Confirm the pid is still the supervisor before signalling it. Pids get
# reused, and SIGUSR1 kills most processes that are not expecting it.
# The redirect is inside a subshell because a missing /proc entry -- the
# ordinary case for a supervisor that has gone away -- is reported by the shell
# itself, before any redirection on the command could suppress it.
if [ -n "$sup" ] &&
	(tr '\0' ' ' < "/proc/$sup/cmdline") 2>/dev/null | grep -q 'waybar-run'; then
	kill -USR1 "$sup" 2>/dev/null && exit 0
fi

# Supervisor is gone too (it died, or was never started for this session):
# start a fresh one, which brings the bar up with it.
exec "$RUNNER"
