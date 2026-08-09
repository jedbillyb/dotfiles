#!/bin/sh
# Touchscreen gestures for sway, via lisgd.
#
# sway's own `bindgesture` only fires on libinput gesture events, which
# touchpads emit and touchscreens do not. lisgd reads raw touch events off the
# evdev node and synthesises swipes from them, so it is what makes edge swipes
# possible at all here.
#
# Reading /dev/input/touchscreen needs the `input` group. That symlink and the
# group ownership come from /etc/udev/rules.d/99-touchscreen-lisgd.rules.
#
# Safe under exec_always: an flock keeps a sway reload from stacking daemons.

DEV=/dev/input/touchscreen
LOCK=/tmp/touch-gestures.lock
# Absolute, not bare `lisgd`: sway hands its children a PATH of just
# /usr/bin:/usr/sbin, so anything in ~/.local/bin is invisible to exec_always.
LISGD=$HOME/.local/bin/lisgd
RESIZE=$HOME/.local/bin/touch-resize.sh
RESIZED=$HOME/.local/bin/touch-resized.py
RESIZED_LOCK=/tmp/touch-resized.lock
WSNEW=$HOME/.local/bin/workspace-new.py

# Passed down to touch-resize.sh through lisgd, so that script does not have to
# fork `id -u` to name it. It is now small enough that a fork would be most of
# the work it does.
TOUCH_RESIZE_FIFO=/tmp/touch-resize-$(id -u).fifo
export TOUCH_RESIZE_FIFO

# Present only while the daemon actually holds a window boundary. touch-resize.sh
# exits non-zero when it is missing, which the patched lisgd takes as "declined"
# and so leaves the swipe intact for whatever release gesture it turns out to be.
TOUCH_RESIZE_GRABBED=/tmp/touch-resize-$(id -u).grabbed
export TOUCH_RESIZE_GRABBED

[ -e "$DEV" ] || { echo "touch-gestures: no $DEV, is the udev rule installed?" >&2; exit 1; }
[ -x "$LISGD" ] || { echo "touch-gestures: no lisgd at $LISGD" >&2; exit 1; }
[ -x "$RESIZE" ] || { echo "touch-gestures: no touch-resize.sh at $RESIZE" >&2; exit 1; }
[ -x "$RESIZED" ] || { echo "touch-gestures: no touch-resized.py at $RESIZED" >&2; exit 1; }
[ -x "$WSNEW" ] || { echo "touch-gestures: no workspace-new.py at $WSNEW" >&2; exit 1; }

# usermod only takes effect at the next login, so on the session where the
# group was first granted this process still lacks it. sg picks the membership
# straight out of /etc/group, no password and no logout. The guard stops an
# infinite re-exec if sg somehow still leaves us without access.
if ! id -nG | tr ' ' '\n' | grep -qx input && [ -z "$TOUCH_GESTURES_SG" ]; then
    TOUCH_GESTURES_SG=1
    export TOUCH_GESTURES_SG
    exec sg input -c "$0"
fi

exec 9>"$LOCK"
flock -n 9 || exit 0

# The resize daemon does all the work behind touch-resize.sh, which is only a
# FIFO write. Supervised rather than just started: if it dies, resizing goes
# silently dead (the writes land in a pipe nobody reads) and nothing else would
# bring it back. Its own flock keeps a second supervisor from starting, since
# this one outlives the shell that spawned it and would otherwise be duplicated
# by the next launch.
(
    # Drop the inherited lock fd first. Without this the supervisor keeps
    # $LOCK held for as long as it lives, so once lisgd is restarted by hand
    # the next launch sees the lock taken and quietly exits -- gestures gone
    # until the whole session restarts.
    exec 9>&-
    exec 8>"$RESIZED_LOCK"
    flock -n 8 || exit 0
    while :; do
        "$RESIZED"
        sleep 1
    done
) &

# Edge swipes switch workspaces, iPad style: drag in from the right edge and
# the workspace to the right comes with your finger.
#
# The same swipe carried two thirds of the way across the screen (L, ~1270px
# here) instead goes to a new *empty* workspace in that direction, via
# workspace-new.py. `workspace next_on_output` only cycles what already exists,
# so without this there is no way to reach somewhere blank to start something in
# -- which matters far more without a keyboard than with one.
#
# Those two bindings must come before the plain ones: lisgd takes the first
# match and a binding written `*` matches every distance, so an L binding listed
# after one would never be reached. Distance is a floor, not a band -- the check
# is `configured <= measured`.
#
# Edge-anchored (R/L) rather than anywhere-on-screen on purpose -- lisgd cannot
# swallow the touches it watches, so a mid-screen swipe would also scroll
# whatever is underneath it. The edge strip is 100px of mostly-dead space (50px
# scaled by -s below).
#
# One finger near a window boundary drags it -- touch-resize.sh does its own hit
# test with 60px of slop, which is how the gap gets a fingertip-sized grab region
# while staying 10px on screen. Away from a
# boundary it is a no-op, so a drag anywhere else on screen is left alone; that
# no-op is what makes binding a *single* finger safe at all, since one finger
# dragging is also how you scroll everything.
#
# The single-finger resize is edge N (nowhere near an edge) rather than * on
# purpose. When a pressed gesture matches, lisgd advances that slot's leg start
# to the current point, so the release gesture afterwards sees only the leftover
# stub of the swipe and no longer registers -- with * the edge swipes below
# would simply never fire. N is what keeps them apart, and it holds for the
# whole drag: the leg start only advances on a match, so a swipe begun at the
# edge keeps measuring from the edge and never looks like edge N.
#
# The cost is that a resize stops once the drag reaches the edge strip, which is
# also roughly where the outermost windows have no boundary left to drag.
#
# The finger count is passed through because it sets how far from the cached
# anchor a fire may stray: two fingers report two anchors a hand's width apart,
# one finger reports one and wants a tight match.
#
# -t is how far a swipe has to travel before it counts at all. 25px is ~4.5mm,
# tuned down from 100 by feel over several rounds. It applies to the
# release-mode gestures only.
#
# Distance was never the reason a swipe failed to register, though. Three
# defaults were, and all three are loosened here:
#
#   -r 45   Direction leniency, in degrees, default 15. A swipe had to be within
#           15 degrees of dead horizontal or it was thrown away -- and a thumb
#           coming in from the edge arcs, so plenty of real swipes missed.
#
#           Raising it alone made things worse, not better, and it took a verbose
#           log to see why: lisgd tests the eight directions in ascending angle
#           order and takes the first whose band contains the swipe, so once the
#           bands overlap a diagonal claims angles belonging to the cardinal
#           after it. At 40 a right-to-left swipe was accepted only between 265
#           and 310 degrees -- 40 degrees of slack anticlockwise, 5 clockwise --
#           and ten of twelve real edge swipes came out as the unbound diagonal
#           URDL and did nothing. That is the "only works one in three".
#
#           patches/lisgd-cardinals-before-diagonals.patch asks the cardinals
#           first, which is what makes a wide leniency behave the way it reads.
#           With that in place 45 is the value that covers the whole circle: every
#           swipe lands in exactly one cardinal band, so there is no angle at
#           which a swipe is silently discarded. Nothing diagonal is bound, so
#           giving the diagonals no room costs nothing.
#
#   -m 5000 The whole gesture must finish this long after touch-down, default
#           800. A slow, deliberate swipe simply never fired. It also gates the
#           pressed path, where the clock restarts on each fire -- so at 1000 a
#           pause of more than a second mid-drag killed resizing until you
#           lifted your fingers.
#
#           3000 was enough until the new-workspace gesture below, which asks for
#           a swipe two thirds of the way across the screen: that is an arm
#           movement rather than a thumb flick, and doing it slowly and
#           deliberately -- which is the point of it -- can take longer than
#           three seconds. The ceiling only ever discards gestures, so raising it
#           costs nothing.
#
#   -s 2.0  Scales the 50px edge strips to 100px. The workspace swipes only count
#           when they start (or end) in one, and starting a little inboard of a
#           50px strip is easy to do without noticing.
#
# -T is how far a finger travels between fires, and so how coarsely a resize
# follows it: 10px is ~1.8mm on this screen. It is the floor on smoothness now
# that a fire costs ~1.2ms rather than 5-60ms, and it was 20 only because fires
# used to be expensive. Going much below this buys nothing -- at ordinary drag
# speeds 10px already fires faster than the display refreshes, so the extra
# updates would be thrown away, while each one still makes clients relayout.
#
# A swipe down from the top edge closes the window. It is the one destructive
# gesture here, so it carries a distance guard the others do not: the M means at
# least a *medium* swipe, a third of the screen height (400px), which is not
# something a stray touch produces. The top edge is otherwise unused -- left and
# right switch workspace, bottom opens the launcher -- and waybar is only 16px of
# the 100px strip, so there is room to start the drag on the window itself.
#
# It is deliberately anchored to an edge rather than bound to two fingers
# anywhere, because edge-anchored is the only kind of release gesture that
# survives here. A *pressed* gesture that matches advances that finger's leg
# start (lisgd.c, touchmotion), and lisgd counts a binding match as success even
# when the command did nothing -- which the resize bindings below usually do,
# since there is rarely a window boundary within 60px. So any release gesture
# starting mid-screen gets ground down to a ~10px stub and reads as no swipe at
# all. That is what killed the old `2,DU,*,M,R` close: a verbose log showed all
# four attempts arriving as swipe -1. A swipe begun in an edge strip is immune,
# because the edge is computed from the touch-down point and stays L/R/T/B for
# the whole drag, so the N-gated resize bindings can never match it.
#
# Three and four fingers are bound to nothing. Those gestures fire on release,
# and a release gesture only counts the fingers whose *own* swipe matched: with
# three or four down one always drifts off direction, the count falls short, and
# nothing happens -- which is exactly why close-window never worked on three.
exec "$LISGD" -d "$DEV" \
    -t 25 \
    -T 10 \
    -r 45 \
    -m 5000 \
    -s 2.0 \
    -g "1,RL,R,L,R,$WSNEW right" \
    -g "1,LR,L,L,R,$WSNEW left" \
    -g "1,RL,R,*,R,swaymsg workspace next_on_output" \
    -g "1,LR,L,*,R,swaymsg workspace prev_on_output" \
    -g "1,DU,B,*,R,$HOME/.local/bin/spotlight" \
    -g "1,LR,N,*,P,$RESIZE right 1" \
    -g "1,RL,N,*,P,$RESIZE left 1" \
    -g "1,UD,N,*,P,$RESIZE down 1" \
    -g "1,DU,N,*,P,$RESIZE up 1" \
    -g "1,UD,T,M,R,swaymsg kill"
