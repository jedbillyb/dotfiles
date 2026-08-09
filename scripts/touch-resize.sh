#!/bin/bash
# Resize the tiled window boundary a touch gesture grabbed.
#
# Bound to lisgd's pressed mode, so this runs once per 60px of finger travel
# *while the drag is happening*, and lisgd blocks in system() until it returns.
# Per-call cost is therefore felt directly as lag, which is what makes the
# split here worth it:
#
#   first call of a drag  -> touch-resize-pick.py works out which boundary was
#                            grabbed (needs the sway tree; ~60ms, mostly the
#                            Python interpreter starting up)
#   every call after that -> this script alone, reusing the cached container:
#                            one swaymsg, ~5ms
#
# So a drag pays the analysis once and then tracks the finger. Doing it all in
# Python cost 49ms per fire, which stutters visibly at 60px increments.

DIR=$1
case "$DIR" in
	left|right) AXIS=width ;;
	up|down)    AXIS=height ;;
	*) echo "usage: touch-resize.sh left|right|up|down" >&2; exit 2 ;;
esac

# Set by the patched lisgd: LISGD_X/Y is where the finger first landed (which
# boundary was grabbed), LISGD_CUR_X/Y is where it is now (where to put it).
[ -n "${LISGD_X:-}" ] && [ -n "${LISGD_Y:-}" ] || exit 0
[ -n "${LISGD_CUR_X:-}" ] && [ -n "${LISGD_CUR_Y:-}" ] || exit 0

# bash, not sh, purely for speed: $EPOCHREALTIME and $UID are builtins, where
# `date` and `id -u` are a fork each. At 20px steps this runs many times a
# second while your fingers are moving, and every fork is latency you can see.
CACHE="/tmp/touch-resize-$UID.cache"
SLOP=60

# Deliberately much wider than SLOP. lisgd tracks each finger in its own slot
# and exports the anchor of whichever one fired, so a two-finger drag reports
# two anchors a hand's width apart. Matching the cache as tightly as the
# boundary pick made every other fire miss, fall through to the picker (60ms
# against 5ms) and rewrite the cache with the other finger's anchor -- the two
# fingers thrashing it between them, which reads as lag punctuated by snaps.
# Scoping the cache is still done here: a grab in a different part of the
# screen is far further away than this.
CACHE_SLOP=250

# The boundary is moved TO the finger, not BY a step. That matters more than it
# sounds: stepping makes the work proportional to how far you drag, so a fast
# drag queues up fires faster than they can run (lisgd blocks on each one) and
# the boundary visibly trails the finger, arriving late. Positioning absolutely
# is idempotent, so a backlog collapses to the newest fire instead of adding up
# -- drag speed stops mattering entirely.
MIN=100  # refuse to drive a window below this; sway would clamp anyway
# Generous, because it only has to cover the pause between two fires of one
# drag, and a slow careful drag can easily leave a second between them. Safe at
# this length because the anchor check below is what actually scopes the cache:
# a grab somewhere else misses it and re-picks, and a grab in the same spot
# meant the same boundary anyway.
TTL_MS=3000

now=${EPOCHREALTIME/./}      # microseconds, no subprocess
now=$((now / 1000))          # -> milliseconds

# Mid-drag: same axis, anchored within a fingertip of where this drag started,
# and recent enough to still be the same drag.
if [ -r "$CACHE" ]; then
	read -r ts cx cy caxis con osize < "$CACHE" || true
	if [ "${caxis:-}" = "$AXIS" ] &&
		[ $((now - ${ts:-0})) -lt "$TTL_MS" ] &&
		[ $((LISGD_X - cx)) -le "$CACHE_SLOP" ] && [ $((cx - LISGD_X)) -le "$CACHE_SLOP" ] &&
		[ $((LISGD_Y - cy)) -le "$CACHE_SLOP" ] && [ $((cy - LISGD_Y)) -le "$CACHE_SLOP" ]; then
		# Bump the timestamp, so the TTL measures the gap *between* fires
		# rather than the age of the drag. Without this the cache goes stale
		# 600ms after the first fire and the drag dies mid-way -- and it dies
		# for good, because the fallback searches near the original anchor,
		# which the boundary has by then been dragged well away from.
		echo "$now $cx $cy $caxis $con $osize" > "$CACHE"
		# Original size plus how far THIS finger has travelled from its own
		# anchor. Both values come from the same slot, so the delta is the same
		# whichever finger fired -- driving it off an absolute finger position
		# instead would make the boundary flip between the two fingers, i.e.
		# oscillate by the width of your grip. Still absolute rather than
		# incremental, so a backlog of fires collapses to the newest.
		if [ "$AXIS" = width ]; then
			size=$((osize + LISGD_CUR_X - LISGD_X))
		else
			size=$((osize + LISGD_CUR_Y - LISGD_Y))
		fi
		[ "$size" -lt "$MIN" ] && size=$MIN
		exec swaymsg -q "[con_id=$con] resize set $AXIS $size px"
	fi
fi

# First call of this drag: find the boundary and record it for the rest.
exec "$(dirname "$(readlink -f "$0")")/touch-resize-pick.py" "$DIR"
