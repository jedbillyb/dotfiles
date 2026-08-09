#!/usr/bin/env python3
"""Work out which tiled window boundary a touch gesture grabbed, and resize it.

Called by touch-resize.sh on the first fire of a drag only -- the shell script
handles every fire after that from the cache this leaves behind, because
starting Python costs ~21ms and lisgd blocks on each call. Do not bind this
directly to a gesture.

Takes a direction (left|right|up|down). lisgd is patched to export
LISGD_X / LISGD_Y, the point the finger first landed; without those there is no
way to know which boundary was meant, so it does nothing.

The point is to make the gap between two windows draggable by finger without
making it any wider on screen. Sway can't do that itself -- find_edge() tests
the hit against border_thickness, so its grab region is exactly the visible
10px. Here the hit test is ours, so SLOP can be as generous as a fingertip
while the gap stays 10px.

Away from any boundary this exits silently, which is what keeps a stray
two-finger swipe in the middle of a window from resizing something at random.
"""

import json
import os
import subprocess
import time
import sys

# How far from a boundary a gesture still counts as grabbing it. A fingertip is
# ~50px on this screen (~5.6 px/mm), so 60 covers a finger placed on the gap
# with a little to spare, without reaching halfway across a narrow window.
SLOP = 60
MIN = 100  # keep in step with touch-resize.sh

# Shared with touch-resize.sh, which reads it on subsequent fires:
#   <epoch ms> <anchor x> <anchor y> <axis> <container id> <size at grab>
# The size is what the grabbed window measured when the drag started. Every
# fire sets it to that plus the firing finger's travel from its own anchor,
# so the shell never has to re-read the tree.
CACHE = f"/tmp/touch-resize-{os.getuid()}.cache"


def sway(*args):
    return subprocess.run(["swaymsg", "-r", *args], capture_output=True, text=True).stdout


def tiled_windows(node, out):
    """Leaf windows in this subtree. Floating nodes are deliberately not
    followed -- only tiled neighbours share a resizable boundary."""
    for child in node.get("nodes", []):
        tiled_windows(child, out)
    if node.get("pid") and node.get("type") == "con" and not node.get("nodes"):
        out.append(node)


def focused_workspace(node, current=None):
    """The workspace containing the focused node.

    Tracking the ancestor beats looking for a workspace marked focused: on a
    multi-output layout more than one workspace is 'visible', and a workspace
    only carries focus itself when it is empty.
    """
    if node.get("type") == "workspace":
        current = node
    if node.get("focused"):
        return current
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        found = focused_workspace(child, current)
        if found is not None:
            return found
    return None


def apply_resize(con, osize, axis):
    """Original size, plus how far the firing finger has moved from its anchor."""
    k = "X" if axis == "width" else "Y"
    delta = int(os.environ[f"LISGD_CUR_{k}"]) - int(os.environ[f"LISGD_{k}"])
    sway(f"[con_id={con}] resize set {axis} {max(osize + delta, MIN)} px")


def write_cache(x, y, axis, con, osize):
    try:
        with open(CACHE, "w") as f:
            f.write(f"{int(time.time() * 1000)} {x} {y} {axis} {con} {osize}")
    except OSError:
        pass


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("left", "right", "up", "down"):
        sys.exit("usage: touch-resize.sh left|right|up|down")
    direction = sys.argv[1]

    try:
        x = int(os.environ["LISGD_X"])
        y = int(os.environ["LISGD_Y"])
    except (KeyError, ValueError):
        # Not launched from a patched lisgd; refuse rather than guess.
        sys.exit(0)

    horizontal = direction in ("left", "right")
    axis = "width" if horizontal else "height"

    tree = json.loads(sway("-t", "get_tree"))
    ws = focused_workspace(tree)
    if ws is None:
        sys.exit(0)

    wins = []
    tiled_windows(ws, wins)
    if len(wins) < 2:
        sys.exit(0)

    # A boundary is where one window ends and another begins. Pair them up by
    # the shared coordinate so the window on the low side can be identified --
    # that is the one whose width/height gets grown or shrunk.
    best = None
    for a in wins:
        ra = a["rect"]
        a_end = ra["x"] + ra["width"] if horizontal else ra["y"] + ra["height"]
        for b in wins:
            if a is b:
                continue
            rb = b["rect"]
            b_start = rb["x"] if horizontal else rb["y"]
            if abs(b_start - a_end) > 2:  # not adjacent
                continue
            # Must actually overlap on the other axis to be a shared edge.
            if horizontal:
                if ra["y"] >= rb["y"] + rb["height"] or rb["y"] >= ra["y"] + ra["height"]:
                    continue
                if not (ra["y"] - SLOP <= y <= ra["y"] + ra["height"] + SLOP):
                    continue
            else:
                if ra["x"] >= rb["x"] + rb["width"] or rb["x"] >= ra["x"] + ra["width"]:
                    continue
                if not (ra["x"] - SLOP <= x <= ra["x"] + ra["width"] + SLOP):
                    continue
            dist = abs((x if horizontal else y) - a_end)
            if dist <= SLOP and (best is None or dist < best[0]):
                best = (dist, a)

    if best is None:
        sys.exit(0)

    _, low_side = best
    con = low_side["id"]
    osize = low_side["rect"]["width"] if horizontal else low_side["rect"]["height"]
    write_cache(x, y, axis, con, osize)
    apply_resize(con, osize, axis)


if __name__ == "__main__":
    main()
