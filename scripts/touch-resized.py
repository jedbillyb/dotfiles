#!/usr/bin/env python3
"""Resident half of touch resize: does all the work, so a fire costs almost nothing.

lisgd blocks in system() on every fire of a pressed gesture, so whatever that
command costs is lag you can feel on your finger. The only way to get it low is
to stop starting programs: this daemon holds the sway IPC socket open and keeps
the drag state in memory, and the thing lisgd actually runs (touch-resize.sh) is
one `sh` that writes a line to a FIFO and exits.

    before: bash (~4ms) + swaymsg fork (~2ms), plus a 60ms Python tree search on
            the first fire of every drag
    now:    sh (~1ms) writing 40 bytes; the resize happens over here, off the
            gesture's critical path entirely

Started and kept alive by touch-gestures.sh. Speaks the i3/sway IPC directly
rather than shelling out to swaymsg, for the same reason.

Line protocol on the FIFO, one fire per line:

    <left|right|up|down> <fingers> <anchor x> <anchor y> <current x> <current y>

Anchor is where the finger first landed (which boundary was grabbed), current is
where it is now (where to put that boundary). Both come from the patched lisgd.
"""

import json
import os
import select
import socket
import struct
import sys
import time

MAGIC = b"i3-ipc"
RUN_COMMAND = 0
GET_TREE = 4

# How far from a boundary a gesture still counts as grabbing it. A fingertip is
# ~50px on this screen (~5.6 px/mm), so 60 covers a finger placed on the gap
# with a little to spare, without reaching halfway across a narrow window.
SLOP = 60
MIN = 100  # refuse to drive a window below this; sway would clamp anyway

# How long a drag's grabbed boundary stays valid between fires. Generous: it
# only has to cover the pause between two fires of one drag, and a slow careful
# drag can easily leave a second between them. What actually scopes it is the
# anchor check -- a grab somewhere else misses and re-picks, and a grab in the
# same place meant the same boundary anyway.
TTL = 3.0

# "I looked here and there is no boundary" expires much faster. One finger
# dragging is also how you scroll, so most one-finger drags are misses and
# remembering them keeps a scroll from re-walking the tree on every fire. But a
# miss must not be remembered long: after failing to grab a gap you will try
# again in the same spot within a second, and that retry has to be able to look.
NEG_TTL = 1.0

# How far from the drag's anchor a fire may land and still count as the same
# drag. lisgd tracks each finger in its own slot and reports whichever one
# fired, so a two-finger drag reports two anchors a hand's width apart and needs
# the wide match; one finger reports one and wants a tight one, so that a
# just-finished drag is not inherited by an unrelated one nearby.
ANCHOR_SLOP = {1: 60, 2: 250}

# touch-gestures.sh exports this to both halves, so they cannot disagree; the
# default is only for running this by hand.
FIFO = os.environ.get("TOUCH_RESIZE_FIFO") or f"/tmp/touch-resize-{os.getuid()}.fifo"


class Sway:
    """Just enough of the i3 IPC to ask for the tree and run a command."""

    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("sway closed the IPC socket")
            buf += chunk
        return buf

    def request(self, mtype, payload=b""):
        self.sock.sendall(MAGIC + struct.pack("=II", len(payload), mtype) + payload)
        header = self._recv(len(MAGIC) + 8)
        length, _ = struct.unpack("=II", header[len(MAGIC):])
        return self._recv(length)

    def command(self, cmd):
        self.request(RUN_COMMAND, cmd.encode())

    def tree(self):
        return json.loads(self.request(GET_TREE))


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


def pick_boundary(tree, x, y, horizontal):
    """The window on the low side of the boundary nearest (x, y), or None.

    A boundary is where one window ends and another begins; the low-side window
    is the one whose width/height is what gets set. Returning None away from any
    boundary is what keeps a stray swipe mid-window from resizing something at
    random -- and is the whole reason a single finger can be bound to this,
    given one finger dragging is also how you scroll.
    """
    ws = focused_workspace(tree)
    if ws is None:
        return None
    wins = []
    tiled_windows(ws, wins)
    if len(wins) < 2:
        return None

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

    return None if best is None else best[1]


class Resizer:
    def __init__(self, sway):
        self.sway = sway
        self.drag = None  # (expiry, x, y, axis, con, osize); con None == a miss

    def fire(self, direction, fingers, x, y, cur_x, cur_y):
        horizontal = direction in ("left", "right")
        axis = "width" if horizontal else "height"

        drag = self.drag
        if drag is not None:
            expiry, dx, dy, daxis, con, osize = drag
            slop = ANCHOR_SLOP.get(fingers, 250)
            same = (
                daxis == axis
                and time.monotonic() < expiry
                and abs(x - dx) <= slop
                and abs(y - dy) <= slop
            )
            if same:
                # Refresh, so the TTL measures the gap *between* fires rather
                # than the age of the drag -- otherwise a long drag goes stale
                # mid-way, and does so for good, because a re-pick would search
                # near the original anchor that the boundary has moved away from.
                ttl = NEG_TTL if con is None else TTL
                self.drag = (time.monotonic() + ttl, dx, dy, daxis, con, osize)
                if con is None:
                    return
                self.resize(con, osize, axis, x, y, cur_x, cur_y)
                return

        # First fire of a drag: work out what was grabbed, and remember it
        # either way.
        low = pick_boundary(self.sway.tree(), x, y, horizontal)
        if low is None:
            self.drag = (time.monotonic() + NEG_TTL, x, y, axis, None, 0)
            return
        osize = low["rect"]["width"] if horizontal else low["rect"]["height"]
        self.drag = (time.monotonic() + TTL, x, y, axis, low["id"], osize)
        self.resize(low["id"], osize, axis, x, y, cur_x, cur_y)

    def resize(self, con, osize, axis, x, y, cur_x, cur_y):
        """Move the boundary *to* the finger, not *by* a step.

        Stepping makes the work proportional to how far you drag, so a fast drag
        queues fires faster than they run and the boundary trails behind. This
        is idempotent, so a backlog collapses to the newest fire instead.

        The delta is this finger's travel from *its own* anchor rather than an
        absolute screen position, because with two fingers down either may fire:
        an absolute position would flip the boundary between them, oscillating
        by the width of your grip.
        """
        delta = (cur_x - x) if axis == "width" else (cur_y - y)
        size = max(osize + delta, MIN)
        self.sway.command(f"[con_id={con}] resize set {axis} {size} px")


def open_fifo():
    try:
        os.mkfifo(FIFO, 0o600)
    except FileExistsError:
        pass
    # O_RDWR, not O_RDONLY: it means this end never sees EOF when a writer
    # exits, so the daemon is not woken spuriously between fires. The writer
    # opens read-write for its own reason -- see touch-resize.sh.
    return os.open(FIFO, os.O_RDWR | os.O_NONBLOCK)


def main():
    swaysock = os.environ.get("SWAYSOCK")
    if not swaysock:
        sys.exit("touch-resized: no SWAYSOCK")

    resizer = Resizer(Sway(swaysock))
    fd = open_fifo()
    buf = b""

    while True:
        select.select([fd], [], [])
        try:
            buf += os.read(fd, 65536)
        except BlockingIOError:
            continue

        lines = buf.split(b"\n")
        buf = lines.pop()  # trailing partial line, if any

        # Only the newest fire matters: each one positions the boundary
        # absolutely, so acting on a backlog would just be replaying stale
        # finger positions on the way to the same place. Dropping them is how a
        # fast drag stays on the finger.
        for line in reversed(lines):
            fields = line.split()
            if len(fields) != 6:
                continue
            try:
                direction = fields[0].decode()
                fingers, x, y, cur_x, cur_y = (int(f) for f in fields[1:])
            except (ValueError, UnicodeDecodeError):
                continue
            if direction not in ("left", "right", "up", "down"):
                continue
            resizer.fire(direction, fingers, x, y, cur_x, cur_y)
            break


if __name__ == "__main__":
    try:
        main()
    except (ConnectionError, KeyboardInterrupt):
        # sway went away; the supervisor in touch-gestures.sh brings us back.
        sys.exit(0)
