#!/usr/bin/env python3
"""A transparent full-screen surface behind wofi, so clicking away dismisses it.

wofi has no dismiss-on-click-outside, and it cannot be faked from outside the
compositor. The two things you would reach for both fail:

  sway focus events   A click focuses the window under it, but sway only emits
                      an event when the focused container actually *changes*.
                      wofi holds keyboard focus as a layer surface without
                      changing that container, so clicking the window you were
                      already using -- the most likely target -- emits nothing.
                      Apps also churn focus on their own (Firefox does it every
                      second or so while playing video), so the event is both
                      incomplete and noisy.

  reading evdev       A mouse or touchpad reports *relative* motion, so the
                      kernel events never say where the pointer is, and sway's
                      IPC has no cursor position to ask for (`get_seats` has
                      devices and focus, no coordinates).

So instead of working out where the click went, put something there to catch it:
a layer-shell surface covering the whole output, fully transparent, that
dismisses wofi on any button or touch it receives. Clicks that land on wofi
never reach it, because wofi's own surface is stacked above.

Started by `bin/spotlight` before wofi, which is what puts it underneath. It
exits when clicked; spotlight treats that as the dismissal.
"""

import gi

# Gdk has to be pinned as well as Gtk: left to itself gi loads the newest
# typelib it can find, which is Gdk 4.0, and GtkLayerShell then fails because it
# wants the 3.0 one already in the process.
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gtk, GtkLayerShell  # noqa: E402


def main():
    window = Gtk.Window()
    # Without an RGBA visual and a draw handler that clears to nothing, GTK
    # paints the theme background and the backdrop is a grey slab over the
    # screen.
    window.set_app_paintable(True)
    visual = window.get_screen().get_rgba_visual()
    if visual:
        window.set_visual(visual)
    window.connect("draw", clear)

    GtkLayerShell.init_for_window(window)
    # TOP, same layer wofi uses. Within a layer, surfaces stack in the order
    # they are created, and spotlight starts this one first -- so it sits above
    # every window but below wofi itself, which is exactly the sandwich needed:
    # it catches clicks meant for anything else while wofi keeps its own.
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.TOP)
    for edge in (
        GtkLayerShell.Edge.LEFT,
        GtkLayerShell.Edge.RIGHT,
        GtkLayerShell.Edge.TOP,
        GtkLayerShell.Edge.BOTTOM,
    ):
        GtkLayerShell.set_anchor(window, edge, True)
    # -1 means "reserve nothing". The default would carve real estate out of the
    # usable area and shove every tiled window aside for as long as the launcher
    # is open.
    GtkLayerShell.set_exclusive_zone(window, -1)
    # Leave the keyboard alone: wofi needs every keystroke, and taking focus
    # here would break typing in the launcher.
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.NONE)

    window.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.TOUCH_MASK)
    window.connect("button-press-event", dismiss)
    window.connect("touch-event", dismiss)
    window.show_all()

    Gtk.main()


def clear(_window, cr):
    """Paint nothing at all, transparently."""
    cr.set_source_rgba(0, 0, 0, 0)
    cr.set_operator(1)  # cairo.OPERATOR_SOURCE, without importing cairo
    cr.paint()
    return False


def dismiss(*_args):
    """Just exit. spotlight waits on whichever of wofi or this ends first, and
    closes the other -- so this process leaving *is* the dismissal, and nothing
    here needs to know wofi's pid."""
    Gtk.main_quit()
    return True


if __name__ == "__main__":
    main()
