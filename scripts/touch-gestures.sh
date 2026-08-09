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

[ -e "$DEV" ] || { echo "touch-gestures: no $DEV, is the udev rule installed?" >&2; exit 1; }
[ -x "$LISGD" ] || { echo "touch-gestures: no lisgd at $LISGD" >&2; exit 1; }
[ -x "$RESIZE" ] || { echo "touch-gestures: no touch-resize.sh at $RESIZE" >&2; exit 1; }

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

# Edge swipes switch workspaces, iPad style: drag in from the right edge and
# the workspace to the right comes with your finger.
#
# Edge-anchored (R/L) rather than anywhere-on-screen on purpose -- lisgd cannot
# swallow the touches it watches, so a mid-screen swipe would also scroll
# whatever is underneath it. The edge strip is 50px of mostly-dead space.
#
# One or two fingers resizes the boundary the gesture started near --
# touch-resize.sh does its own hit test with 60px of slop, which is how the gap
# gets a fingertip-sized grab region while staying 10px on screen. Away from a
# boundary it is a no-op, so a drag anywhere else on screen is left alone; that
# no-op is what makes binding a *single* finger safe at all, since one finger
# dragging is also how you scroll everything.
#
# The single-finger resize is edge N (nowhere near an edge) rather than * on
# purpose. Pressed gestures fire during the drag and resetslot() the moment they
# match, which would eat the pending release gesture -- with * the edge swipes
# below would simply never fire. The cost is that a resize stops once the drag
# reaches the 50px edge strip, which is also roughly where the outermost windows
# have no boundary left to drag.
#
# The finger count is passed through because it sets how far from the cached
# anchor a fire may stray: two fingers report two anchors a hand's width apart,
# one finger reports one and wants a tight match.
#
# Four fingers resizes the focused window from anywhere, no aiming. It stays
# because two fingers cannot be made exclusive: a browser reads a 2-finger
# horizontal swipe as back/forward, and lisgd cannot swallow the touch.
exec "$LISGD" -d "$DEV" \
    -t 100 \
    -T 20 \
    -m 1000 \
    -g "1,RL,R,*,R,swaymsg workspace next_on_output" \
    -g "1,LR,L,*,R,swaymsg workspace prev_on_output" \
    -g "1,DU,B,*,R,$HOME/.local/bin/spotlight" \
    -g "1,LR,N,*,P,$RESIZE right 1" \
    -g "1,RL,N,*,P,$RESIZE left 1" \
    -g "1,UD,N,*,P,$RESIZE down 1" \
    -g "1,DU,N,*,P,$RESIZE up 1" \
    -g "2,LR,*,*,P,$RESIZE right 2" \
    -g "2,RL,*,*,P,$RESIZE left 2" \
    -g "2,UD,*,*,P,$RESIZE down 2" \
    -g "2,DU,*,*,P,$RESIZE up 2" \
    -g "4,LR,*,*,R,swaymsg resize grow width 60 px" \
    -g "4,RL,*,*,R,swaymsg resize shrink width 60 px" \
    -g "4,UD,*,*,R,swaymsg resize grow height 60 px" \
    -g "4,DU,*,*,R,swaymsg resize shrink height 60 px" \
    -g "3,RL,*,*,R,swaymsg focus right" \
    -g "3,LR,*,*,R,swaymsg focus left" \
    -g "3,DU,*,*,R,swaymsg fullscreen toggle" \
    -g "3,UD,*,*,R,swaymsg kill"
