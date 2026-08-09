#!/usr/bin/env python3
"""Wide strips along the gesture edges that catch swipes but pass taps through.

lisgd reads the touchscreen passively off its evdev node -- that is what lets it
see gestures at all, but it means the compositor still hands those same touches
to whatever is underneath, so an edge swipe also scrolls or drags the app it
started on. Reading evdev cannot prevent that, and an exclusive grab would take
touch away from every app entirely.

The only thing that stops the app seeing a touch is another surface taking it
first, so these strips sit above the windows along each gesture edge and receive
it themselves. Wayland keeps touch focus on the surface that got the touch-down
until the finger lifts, so shielding the *start* of a swipe shields all of it,
however far it travels.

That alone would make the strips dead zones, which is why they were once only as
wide as the window gap. Instead they now hand back what they should not have
taken: a touch that turns out to be a *tap* rather than a swipe is replayed to
the app underneath as a click -- clear the input regions, drive sway's own cursor
over the spot, click, restore the regions. So the strips can be wide enough to
catch a swipe reliably while a tap still lands on the button you aimed at.

What that cannot give back is a *drag* that starts inside a strip and is not a
swipe -- scrolling a page from within the last 100px, say. Replaying a press is
one command; replaying a live drag would mean tracking it the whole way. Swipes
are what these edges are for.

The strips are on the `top` layer, which leaves waybar and the launcher (both
`overlay`) above and untouched.

  TOUCH_SHIELD_WIDTH   strip thickness in px (default 100)
  TOUCH_SHIELD_DEBUG=1 tint them, since placing an invisible surface is
                       otherwise guesswork
"""

import fcntl
import os
import subprocess
import sys
import time

import cairo
import gi

# Gdk has to be pinned as well as Gtk: left to itself gi loads the newest
# typelib it can find, which is Gdk 4.0, and GtkLayerShell then fails because it
# wants the 3.0 one already in the process.
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

LOCK = "/tmp/touch-shield.lock"
WIDTH = int(os.environ.get("TOUCH_SHIELD_WIDTH", "100"))
DEBUG = os.environ.get("TOUCH_SHIELD_DEBUG") == "1"

# What still counts as a tap rather than the start of a swipe. A fingertip is
# ~50px across here and rolls a little as it lifts, so a few px of travel means
# nothing; 25 stays under what lisgd needs to call something a swipe.
TAP_SLOP = 25
TAP_MS = 500

# Long enough for sway to deliver the replayed click before the strips start
# claiming input again.
RESTORE_MS = 120

EDGES = ("left", "right", "bottom")

windows = {}


def sway(*args):
    subprocess.run(["swaymsg", "-q", *args], check=False)


def screen_size():
    geometry = Gdk.Display.get_default().get_monitor(0).get_geometry()
    return geometry.width, geometry.height


def origin(edge, screen_w, screen_h):
    """Top-left of a strip in screen coordinates.

    Touch events arrive relative to the surface while the replayed click has to
    be aimed in screen coordinates, so the two need bridging.
    """
    if edge == "left":
        return 0, 0
    if edge == "right":
        return screen_w - WIDTH, 0
    return 0, screen_h - WIDTH


def passthrough(enabled):
    """Make every strip transparent to input, or claim input again.

    An empty input region is what lets the replayed click reach the app instead
    of bouncing straight back off the strip replaying it.
    """
    for window in windows.values():
        gdk_window = window.get_window()
        if gdk_window is None:
            continue
        # None means "no input shape at all", i.e. back to the whole surface.
        # Handing back a full-size rectangle instead looks equivalent and is
        # not: the strip went permanently deaf after one click, because the
        # GdkWindow's idea of its own size is not the surface size here.
        region = cairo.Region() if enabled else None
        gdk_window.input_shape_combine_region(region, 0, 0)


def give_back(x=None, y=None):
    """Hand an input the strip should not have taken back to the app underneath.

    With no coordinates this is a mouse click, and sway's pointer is already
    exactly where the user put it -- only touch needs the cursor moved first.
    """
    if DEBUG:
        print(f"giving back at {x},{y}" if x is not None else "giving back a click", flush=True)
    passthrough(True)
    if x is not None:
        sway("seat", "seat0", "cursor", "set", str(x), str(y))
    sway("seat", "seat0", "cursor", "press", "button1")
    sway("seat", "seat0", "cursor", "release", "button1")
    GLib.timeout_add(RESTORE_MS, lambda: (passthrough(False), False)[1])


class Touch:
    """The one in-flight touch on a strip.

    Only one is tracked: a second finger means a two-finger gesture, which is
    lisgd's business and never a tap to hand back.
    """

    def __init__(self):
        self.start = None
        self.moved = False

    def begin(self, x, y):
        self.start = (x, y, time.monotonic())
        self.moved = False

    def update(self, x, y):
        if self.start is None:
            return
        sx, sy, _ = self.start
        if abs(x - sx) > TAP_SLOP or abs(y - sy) > TAP_SLOP:
            self.moved = True

    def was_tap(self):
        if self.start is None or self.moved:
            return False
        return time.monotonic() - self.start[2] < TAP_MS / 1000


def on_touch(_widget, event, edge, screen):
    touch = windows[edge].touch
    ox, oy = origin(edge, *screen)
    x, y = ox + int(event.x), oy + int(event.y)

    if event.type == Gdk.EventType.TOUCH_BEGIN:
        touch.begin(x, y)
    elif event.type == Gdk.EventType.TOUCH_UPDATE:
        touch.update(x, y)
    elif event.type == Gdk.EventType.TOUCH_END:
        if touch.was_tap():
            give_back(x, y)
        touch.start = None
    elif event.type == Gdk.EventType.TOUCH_CANCEL:
        touch.start = None
    return True


def on_button(_widget, _event):
    """A mouse click is never a swipe, so give it straight back."""
    give_back()
    return True


def clear(_window, cr):
    """Paint nothing at all, transparently -- unless debugging the geometry."""
    cr.set_source_rgba(1, 0, 0, 0.25) if DEBUG else cr.set_source_rgba(0, 0, 0, 0)
    cr.set_operator(cairo.OPERATOR_SOURCE)
    cr.paint()
    return False


def strip(edge, screen):
    window = Gtk.Window()
    window.set_app_paintable(True)
    visual = window.get_screen().get_rgba_visual()
    if visual:
        window.set_visual(visual)
    window.connect("draw", clear)

    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.TOP)
    GtkLayerShell.set_namespace(window, "touch-shield")

    opposite = {
        "left": GtkLayerShell.Edge.RIGHT,
        "right": GtkLayerShell.Edge.LEFT,
        "bottom": GtkLayerShell.Edge.TOP,
    }[edge]
    for e in (
        GtkLayerShell.Edge.LEFT,
        GtkLayerShell.Edge.RIGHT,
        GtkLayerShell.Edge.TOP,
        GtkLayerShell.Edge.BOTTOM,
    ):
        # Anchored to everything but the far side, so the strip runs the length
        # of its edge and takes its thickness from the size request below.
        GtkLayerShell.set_anchor(window, e, e != opposite)

    # -1 reserves nothing. The default would carve the strip out of the usable
    # area and shove every tiled window inward by its width.
    GtkLayerShell.set_exclusive_zone(window, -1)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.NONE)

    if edge == "bottom":
        window.set_size_request(-1, WIDTH)
    else:
        window.set_size_request(WIDTH, -1)

    window.add_events(Gdk.EventMask.TOUCH_MASK | Gdk.EventMask.BUTTON_PRESS_MASK)
    window.connect("touch-event", on_touch, edge, screen)
    window.connect("button-press-event", on_button)
    window.show_all()
    window.touch = Touch()
    return window


def main():
    # Safe under exec_always: a sway reload would otherwise stack a second set
    # of strips on top of the first.
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)

    screen = screen_size()
    for edge in EDGES:
        windows[edge] = strip(edge, screen)
    Gtk.main()


if __name__ == "__main__":
    main()
