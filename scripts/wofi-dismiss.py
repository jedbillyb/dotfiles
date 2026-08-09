#!/usr/bin/env python3
"""Close wofi when you tap or click away from it, the way a dialog dismisses.

wofi has no option for this, and neither input path is served by the other, so
this watches both:

  touch  Read touch-downs straight off the evdev node (the same
         /dev/input/touchscreen the gesture daemon uses, hence the same `input`
         group requirement) and compare them against the rectangle wofi was told
         to occupy. Necessary because wofi holds keyboard focus as a *layer
         surface*: a tap elsewhere raises no sway event at all, and on an empty
         workspace -- exactly when you reach for a launcher -- there would be no
         other window to focus even in principle.

  click  Subscribe to sway's window events and dismiss on a focus change. A
         click *does* focus the window under it, even with wofi up. This cannot
         be done the touch way, because a mouse or touchpad reports relative
         motion, so evdev alone never says where the pointer is; and sway's IPC
         has no cursor position to ask for either (`get_seats` carries devices
         and focus, no coordinates).

The gap that leaves is a click on bare wallpaper with no window under it, which
raises no focus event. Touch covers it; a mouse does not. Closing that properly
would mean rendering a full-screen layer surface behind wofi to catch the click,
which is a Wayland client in its own right.

Started and stopped by `bin/spotlight`, which knows the rectangle because it
computes it in order to centre the box.

The tap or click still reaches whatever is underneath -- nothing here can
swallow it, just as lisgd cannot. That matches dismissing a dialog elsewhere.

usage: wofi-dismiss.py X Y W H SCREEN_W SCREEN_H WOFI_PID
"""

import array
import fcntl
import json
import os
import select
import signal
import socket
import struct
import sys
import time

DEV = os.environ.get("WOFI_TAP_DEV", "/dev/input/touchscreen")

# linux/input.h
EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
BTN_TOUCH = 0x14A
ABS_X, ABS_Y = 0x00, 0x01
ABS_MT_POSITION_X, ABS_MT_POSITION_Y = 0x35, 0x36

# struct input_event: two longs of timeval, then type, code, value
EVENT_FMT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)

# struct input_absinfo: value, minimum, maximum, fuzz, flat, resolution
ABSINFO_FMT = "6i"

# sway IPC
IPC_MAGIC = b"i3-ipc"
IPC_SUBSCRIBE = 2

# Focus events are ignored for this long after startup, so the shuffle around
# wofi mapping cannot dismiss it before it is even on screen.
GRACE = 0.4


def absinfo(fd, axis):
    """Range of an absolute axis, via EVIOCGABS.

    The digitiser reports in its own units, not pixels, so the raw numbers mean
    nothing until scaled by this.
    """
    size = struct.calcsize(ABSINFO_FMT)
    # _IOR('E', 0x40 + axis, struct input_absinfo)
    request = (2 << 30) | (size << 16) | (ord("E") << 8) | (0x40 + axis)
    buf = array.array("i", [0] * 6)
    try:
        fcntl.ioctl(fd, request, buf, True)
    except OSError:
        return None
    _, minimum, maximum = buf[0], buf[1], buf[2]
    if maximum <= minimum:
        return None
    return minimum, maximum


def sway_window_events():
    """A sway IPC socket subscribed to window events, or None.

    Only used as a click detector: sway focuses the window under a click even
    while wofi is up, and that focus change is the one signal a pointer leaves
    behind.
    """
    path = os.environ.get("SWAYSOCK")
    if not path:
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
        payload = b'["window"]'
        sock.sendall(IPC_MAGIC + struct.pack("=II", len(payload), IPC_SUBSCRIBE) + payload)
    except OSError:
        return None
    return sock


def focus_changed(sock):
    """True if any window took focus. Anything else on the socket is ignored."""
    try:
        data = sock.recv(65536)
    except OSError:
        return False
    if not data:
        raise ConnectionError
    changed = False
    while len(data) >= len(IPC_MAGIC) + 8:
        length, _ = struct.unpack("=II", data[len(IPC_MAGIC):len(IPC_MAGIC) + 8])
        body = data[len(IPC_MAGIC) + 8:len(IPC_MAGIC) + 8 + length]
        data = data[len(IPC_MAGIC) + 8 + length:]
        try:
            if json.loads(body).get("change") == "focus":
                changed = True
        except (ValueError, UnicodeDecodeError):
            pass
    return changed


def main():
    if len(sys.argv) != 8:
        sys.exit(__doc__.strip().splitlines()[-1])
    x, y, w, h, screen_w, screen_h, wofi_pid = (int(a) for a in sys.argv[1:])
    started = time.monotonic()

    events = sway_window_events()
    try:
        fd = os.open(DEV, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        # No touchscreen, or no permission. Not worth complaining about: the
        # launcher still works by keyboard, and clicks are still watched.
        fd = None
    if fd is None and events is None:
        sys.exit(0)

    def dismiss():
        try:
            os.kill(wofi_pid, signal.SIGTERM)
        except OSError:
            pass

    ranges = {}
    for axis in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_X, ABS_Y):
        got = absinfo(fd, axis) if fd is not None else None
        if got:
            ranges[axis] = got

    def to_px(axis, raw, span):
        rng = ranges.get(axis)
        if not rng:
            # A device that will not report its range cannot be scaled, so take
            # the value as given rather than dropping the tap entirely.
            return raw
        low, high = rng
        return int((raw - low) * span / (high - low))

    pos_x = pos_y = None
    went_down = False
    buf = b""

    watch = [f for f in (fd, events) if f is not None]

    while True:
        # The timeout is what notices wofi being dismissed some other way (a
        # pick, Escape, or its own exit); there is no event to wait on for that.
        ready, _, _ = select.select(watch, [], [], 0.25)
        try:
            os.kill(wofi_pid, 0)
        except OSError:
            return
        if not ready:
            continue

        if events is not None and events in ready:
            try:
                if focus_changed(events) and time.monotonic() - started > GRACE:
                    dismiss()
                    return
            except ConnectionError:
                watch.remove(events)
                events = None

        if fd is None or fd not in ready:
            continue

        try:
            buf += os.read(fd, EVENT_SIZE * 64)
        except (BlockingIOError, OSError):
            continue

        while len(buf) >= EVENT_SIZE:
            chunk, buf = buf[:EVENT_SIZE], buf[EVENT_SIZE:]
            _, _, etype, code, value = struct.unpack(EVENT_FMT, chunk)

            if etype == EV_ABS:
                if code in (ABS_MT_POSITION_X, ABS_X):
                    pos_x = to_px(code, value, screen_w)
                elif code in (ABS_MT_POSITION_Y, ABS_Y):
                    pos_y = to_px(code, value, screen_h)
            elif etype == EV_KEY and code == BTN_TOUCH and value == 1:
                went_down = True
            elif etype == EV_SYN:
                # Decide at the end of the packet, not on the BTN_TOUCH event:
                # the coordinates for a new contact may be reported either side
                # of it within the same packet.
                if went_down and pos_x is not None and pos_y is not None:
                    outside = not (x <= pos_x <= x + w and y <= pos_y <= y + h)
                    if outside:
                        dismiss()
                        return
                went_down = False


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
