#!/usr/bin/env python3
"""Hide waybar while a fullscreen window is showing, bring it back after.

Why not just let the fullscreen window cover the bar: sway keeps the bar's
exclusive zone reserved even when fullscreen hides it, so dunst (which places
popups below every exclusive zone) leaves a 16px hole above each notification.
Making the bar invisible unmaps it, the zone goes away, and popups sit at the
very top of the screen.

waybar has `"ipc": true, "id": "waybar"` and sway/config has a matching
`bar { id waybar }` block, so `swaymsg bar waybar mode invisible|dock` controls
it. Those commands are idempotent, so this never drifts out of sync the way a
SIGUSR1 toggle would.

Started from sway/config with exec_always; a lock file makes reloads hand over
to the running copy instead of stacking a second one.
"""
import fcntl
import json
import os
import subprocess
import sys

BAR_ID = "waybar"
LOCK = f"/tmp/fullscreen-bar.{os.getuid()}.{os.environ.get('WAYLAND_DISPLAY', 'x')}.lock"


def fullscreen_visible(tree):
    """True if any visible window is fullscreen."""
    stack = [tree]
    while stack:
        n = stack.pop()
        if n.get("fullscreen_mode", 0) and n.get("visible") and n.get("pid"):
            return True
        stack.extend(n.get("nodes", []))
        stack.extend(n.get("floating_nodes", []))
    return False


def get_tree():
    out = subprocess.run(["swaymsg", "-r", "-t", "get_tree"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def set_mode(mode):
    subprocess.run(["swaymsg", "-q", "bar", BAR_ID, "mode", mode])


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(0)  # already running

    current = None

    def sync():
        nonlocal current
        want = "invisible" if fullscreen_visible(get_tree()) else "dock"
        if want != current:
            set_mode(want)
            current = want

    sync()
    sub = subprocess.Popen(
        ["swaymsg", "-r", "-m", "-t", "subscribe", '["window","workspace"]'],
        stdout=subprocess.PIPE, text=True)
    for _ in sub.stdout:
        sync()


if __name__ == "__main__":
    main()
