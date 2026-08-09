#!/bin/sh
# Hand one touch-resize fire to the daemon. Nothing else.
#
# This is what lisgd runs, and lisgd blocks in system() until it returns, so its
# cost is lag on your finger. Everything it used to do -- reading the sway tree,
# working out which boundary was grabbed, sending the resize -- now lives in
# touch-resized.py, which is already running and already connected to sway. What
# is left is one `sh` writing 40 bytes, about a millisecond.
#
# Opening the FIFO read-write, rather than write-only, is what makes this safe:
# a write-only open *blocks* until something opens the read end, so if the
# daemon were dead every gesture would hang lisgd for good. Read-write never
# blocks (the opener is its own reader), so with no daemon the line simply goes
# nowhere and touch resize quietly does nothing.

DIR=$1
NFINGERS=${2:-2}
# Exported by touch-gestures.sh and inherited through lisgd, rather than worked
# out here: `id -u` would be a fork, and at this size a fork is most of the cost.
FIFO=$TOUCH_RESIZE_FIFO
GRABBED=$TOUCH_RESIZE_GRABBED

# Set by the patched lisgd: LISGD_X/Y is where the finger first landed (which
# boundary was grabbed), LISGD_CUR_X/Y is where it is now (where to put it).
[ -n "$LISGD_X" ] && [ -n "$LISGD_CUR_X" ] || exit 1
[ -p "$FIFO" ] || exit 1

exec 3<>"$FIFO" || exit 1
printf '%s %s %s %s %s %s\n' \
	"$DIR" "$NFINGERS" "$LISGD_X" "$LISGD_Y" "$LISGD_CUR_X" "$LISGD_CUR_Y" >&3

# The exit status tells the patched lisgd whether this gesture was really a
# resize. Most one-finger drags are not -- dragging is also how you scroll, and
# there is usually no window boundary within reach -- and until lisgd could be
# told so, every one of them consumed the swipe it was part of: a pressed match
# advances the slot's leg start, so a swipe aimed at an edge that began slightly
# inboard arrived at touch-up measuring about 10px and read as no swipe at all.
# That is what stopped close-window and any other mid-screen release gesture
# from ever firing.
#
# The daemon keeps this file present exactly while it holds a boundary, so the
# test is one syscall here and the decision stays where the knowledge is. Note
# the line above is written either way: declining tells lisgd not to eat the
# swipe, it does not mean the fire should be dropped.
[ -e "$GRABBED" ] || exit 1
