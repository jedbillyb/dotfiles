#!/usr/bin/env python3
"""Close wofi when you tap outside its box, the way tapping off a dialog works.

wofi has no such option, and it cannot be faked through sway either: it takes
keyboard focus as a layer surface, so tapping elsewhere raises no focus event to
hang this off. Watching for a focus change would also fail in the most common
case of all -- opening the launcher on an empty workspace, where there is no
other window to focus.

So this reads touch-downs straight off the evdev node (the same
/dev/input/touchscreen the gesture daemon uses, hence the same `input` group
requirement) and compares them against the rectangle wofi was told to occupy.
Started and stopped by `bin/spotlight`, which knows that rectangle because it
computes it.

The tap still reaches whatever is underneath -- nothing here can swallow it,
just as lisgd cannot. That matches how tapping off a dialog behaves elsewhere.

usage: wofi-tap-dismiss.py X Y W H SCREEN_W SCREEN_H WOFI_PID
"""

import array
import fcntl
import os
import select
import signal
import struct
import sys

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


def main():
    if len(sys.argv) != 8:
        sys.exit(__doc__.strip().splitlines()[-1])
    x, y, w, h, screen_w, screen_h, wofi_pid = (int(a) for a in sys.argv[1:])

    try:
        fd = os.open(DEV, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        # No touchscreen, or no permission: the launcher still works by
        # keyboard, so this is not worth complaining about.
        sys.exit(0)

    ranges = {}
    for axis in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_X, ABS_Y):
        got = absinfo(fd, axis)
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

    while True:
        # The timeout is what notices wofi being dismissed some other way (a
        # pick, Escape, or its own exit); there is no event to wait on for that.
        ready, _, _ = select.select([fd], [], [], 0.25)
        try:
            os.kill(wofi_pid, 0)
        except OSError:
            return
        if not ready:
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
                        try:
                            os.kill(wofi_pid, signal.SIGTERM)
                        except OSError:
                            pass
                        return
                went_down = False


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
