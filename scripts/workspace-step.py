#!/usr/bin/env python3
"""Step one workspace along by number, creating it if it does not exist.

This is the two-finger edge swipe, and it is deliberately different from the
one-finger one. `workspace next_on_output` walks the workspaces that *exist*, so
from 3 it might jump to 9; this walks the numbers, so from 3 it goes to 4 and
back to 3, whatever is or is not on them. That makes the two-finger swipe the
predictable one -- the workspace you land on depends only on where you started
and which way you went, never on what happens to be open.

Creating on demand is the whole point: it is how you reach somewhere blank to
start something in, which matters far more without a keyboard than with one. But
an occupied number is not skipped over to find a free one. Asked for 5, you get
5, empty or not.

The only thing it will not do is go below 1, since sway numbers start there.

Usage: workspace-step.py <left|right>
"""

import json
import os
import socket
import struct
import sys

MAGIC = b"i3-ipc"
RUN_COMMAND = 0
GET_WORKSPACES = 1


def request(sock, mtype, payload=b""):
    sock.sendall(MAGIC + struct.pack("=II", len(payload), mtype) + payload)
    header = b""
    while len(header) < len(MAGIC) + 8:
        chunk = sock.recv(len(MAGIC) + 8 - len(header))
        if not chunk:
            sys.exit("workspace-step: sway closed the IPC socket")
        header += chunk
    length, _ = struct.unpack("=II", header[len(MAGIC):])
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            sys.exit("workspace-step: sway closed the IPC socket")
        body += chunk
    return body


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("left", "right"):
        sys.exit("usage: workspace-step.py <left|right>")
    step = 1 if sys.argv[1] == "right" else -1

    swaysock = os.environ.get("SWAYSOCK")
    if not swaysock:
        sys.exit("workspace-step: no SWAYSOCK")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(swaysock)

    # get_workspaces rather than the tree: it reports `focused` directly, and
    # there is nothing here that needs to know what is open on any of them.
    workspaces = json.loads(request(sock, GET_WORKSPACES))
    current = next((w for w in workspaces if w.get("focused")), None)
    if current is None or current.get("num", -1) < 1:
        return

    target = current["num"] + step
    if target < 1:
        return

    request(sock, RUN_COMMAND, f"workspace number {target}".encode())


if __name__ == "__main__":
    main()
