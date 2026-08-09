#!/bin/sh
# Resize the tiled window boundary a touch gesture grabbed.
#
# Bound to lisgd's pressed mode, so this runs once per 60px of finger travel
# *while the drag is happening*, and lisgd blocks in system() until it returns.
# Per-call cost is therefore felt directly as lag, which is what makes the
# split here worth it:
#
#   first call of a drag  -> touch-resize-pick.py works out which boundary was
#                            grabbed (needs the sway tree; ~50ms, mostly the
#                            Python interpreter starting up)
#   every call after that -> this script alone, reusing the cached container:
#                            one swaymsg, ~4ms
#
# So a drag pays the analysis once and then tracks the finger. Doing it all in
# Python cost 49ms per fire, which stutters visibly at 60px increments.

DIR=$1
case "$DIR" in
	left|right) AXIS=width ;;
	up|down)    AXIS=height ;;
	*) echo "usage: touch-resize.sh left|right|up|down" >&2; exit 2 ;;
esac

# Set by the patched lisgd: where the finger first landed. Without it there is
# no way to know which boundary was meant, so do nothing rather than guess.
[ -n "${LISGD_X:-}" ] && [ -n "${LISGD_Y:-}" ] || exit 0

CACHE="/tmp/touch-resize-$(id -u).cache"
SLOP=60
# Generous, because it only has to cover the pause between two fires of one
# drag, and a slow careful drag can easily leave a second between them. Safe at
# this length because the anchor check below is what actually scopes the cache:
# a grab somewhere else misses it and re-picks, and a grab in the same spot
# meant the same boundary anyway.
TTL_MS=3000

case "$DIR" in
	right|down) OP=grow ;;
	*)          OP=shrink ;;
esac

now=$(($(date +%s%N) / 1000000))

# Mid-drag: same axis, anchored within a fingertip of where this drag started,
# and recent enough to still be the same drag.
if [ -r "$CACHE" ]; then
	read -r ts cx cy caxis con < "$CACHE" || true
	if [ "${caxis:-}" = "$AXIS" ] &&
		[ $((now - ${ts:-0})) -lt "$TTL_MS" ] &&
		[ $((LISGD_X - cx)) -le "$SLOP" ] && [ $((cx - LISGD_X)) -le "$SLOP" ] &&
		[ $((LISGD_Y - cy)) -le "$SLOP" ] && [ $((cy - LISGD_Y)) -le "$SLOP" ]; then
		# Bump the timestamp, so the TTL measures the gap *between* fires
		# rather than the age of the drag. Without this the cache goes stale
		# 600ms after the first fire and the drag dies mid-way -- and it dies
		# for good, because the fallback searches near the original anchor,
		# which the boundary has by then been dragged well away from.
		echo "$now $cx $cy $caxis $con" > "$CACHE"
		exec swaymsg -q "[con_id=$con] resize $OP $AXIS 60 px"
	fi
fi

# First call of this drag: find the boundary and record it for the rest.
exec "$(dirname "$(readlink -f "$0")")/touch-resize-pick.py" "$DIR"
