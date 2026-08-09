#!/usr/bin/env python3
"""Switch to a new, empty workspace in one direction.

`workspace next_on_output` only ever cycles the workspaces that already exist,
so there is no way to swipe your way to somewhere blank and start something new
-- which is the one thing a touchscreen session most wants, having no keyboard
shortcut to fall back on. This picks the nearest *unused* number in the given
direction and switches to it, which sway creates on demand.

Numbers here are sparse (1, 2, 9, 10), so "the next one along" means the nearest
free number rather than one past the end: going right from 1 lands on 3, not 11.
That keeps a new workspace next to where you were instead of far away.

Two deliberate no-ops:

  * Going left from the lowest workspace, since sway numbers start at 1 and
    there is nothing below it to create.
  * Asking for an empty workspace while already on one. Otherwise a repeated
    swipe walks off into a trail of empties, and the gesture that produced it is
    a long drag that is easy to do twice.

Usage: workspace-new.py <left|right>
"""

import json
import os
import socket
import struct
import sys

MAGIC = b"i3-ipc"
RUN_COMMAND = 0
GET_TREE = 4


def request(sock, mtype, payload=b""):
    sock.sendall(MAGIC + struct.pack("=II", len(payload), mtype) + payload)
    header = b""
    while len(header) < len(MAGIC) + 8:
        chunk = sock.recv(len(MAGIC) + 8 - len(header))
        if not chunk:
            sys.exit("workspace-new: sway closed the IPC socket")
        header += chunk
    length, _ = struct.unpack("=II", header[len(MAGIC):])
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            sys.exit("workspace-new: sway closed the IPC socket")
        body += chunk
    return body


def walk_workspaces(node, out):
    if node.get("type") == "workspace":
        out.append(node)
        return
    for child in node.get("nodes", []):
        walk_workspaces(child, out)


def has_windows(ws):
    """Whether anything at all lives on this workspace, floating included."""
    stack = [ws]
    while stack:
        node = stack.pop()
        if node is not ws and node.get("pid"):
            return True
        stack.extend(node.get("nodes", []))
        stack.extend(node.get("floating_nodes", []))
    return False


def contains_focus(node):
    if node.get("focused"):
        return True
    return any(
        contains_focus(child)
        for child in node.get("nodes", []) + node.get("floating_nodes", [])
    )


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("left", "right"):
        sys.exit("usage: workspace-new.py <left|right>")
    direction = sys.argv[1]

    swaysock = os.environ.get("SWAYSOCK")
    if not swaysock:
        sys.exit("workspace-new: no SWAYSOCK")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(swaysock)

    tree = json.loads(request(sock, GET_TREE))
    workspaces = []
    walk_workspaces(tree, workspaces)
    # Skip sway's internal scratchpad workspace, which has num -1.
    numbered = [w for w in workspaces if w.get("num", -1) > 0]
    if not numbered:
        return

    current = next((w for w in numbered if contains_focus(w)), None)
    if current is None:
        return
    # Already somewhere blank: this gesture has nothing left to do.
    if not has_windows(current):
        return

    used = {w["num"] for w in numbered}
    if direction == "right":
        target = current["num"] + 1
        while target in used:
            target += 1
    else:
        target = current["num"] - 1
        while target in used:
            target -= 1
        if target < 1:
            return  # nothing below workspace 1 to create

    request(sock, RUN_COMMAND, f"workspace number {target}".encode())


if __name__ == "__main__":
    main()
