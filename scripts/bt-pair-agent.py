#!/usr/bin/env python3
"""Bluetooth pairing agent that asks before letting anything bond.

Replaces both agents that would otherwise handle pairing here:

  * ancs4linux's, whose RequestConfirmation emits the passkey as a notification
    and returns -- and returning is how BlueZ is told the user consented. It
    accepts every bond, so a stranger only had to tap "Pair" on their own
    device. The code it showed was never compared to anything, so it was always
    "right".
  * blueman's, which does ask, but is not guaranteed to be running in this
    session and does not honour the answer the way this does.

Numeric comparison is the only association model available (see CAPABILITY
below -- passkey entry breaks ANCS), so the code always matching is expected:
both sides derive the same six digits from the pairing exchange. It defends
against a man in the middle, not against a stranger tapping Pair. The gate
that stops the stranger is THIS side's prompt, so the prompt has to be real
and its answer has to be honoured.

Runs as your user from the sway session so it can put the prompt on screen.
Registering a BlueZ agent as an unprivileged user is allowed; blueman does the
same.
"""

import logging
import os
import subprocess
import shutil
import sys
import threading
import tempfile
import time

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

AGENT_PATH = "/org/jedbillyb/BtPairAgent"

# DisplayYesNo, not KeyboardOnly, and this is load-bearing for ANCS rather than
# a UI preference.
#
# KeyboardOnly makes us look like a keyboard-class accessory, and iOS then
# bonds over classic BR/EDR and derives the LE keys from that link key. A
# classic-led bond gets filed as an ordinary Bluetooth accessory, so iOS never
# offers notification access -- no prompt at pairing, no Show Notifications
# toggle afterwards, and the ANCS subscribe silently returns data forever. The
# only visible trace is a [LinkKey] section in the stored bond.
#
# DisplayYesNo gets Numeric Comparison and a BLE-style bond, which is what iOS
# wants to see before it will treat us as a notification peripheral. The
# confirmation is weaker than typing the code, so make it a real prompt whose
# answer is honoured -- upstream's simply returns, which is how it accepts
# every bond.
CAPABILITY = "DisplayYesNo"

# Seconds the pairing prompt stays on screen before it refuses by default.
CONFIRM_TIMEOUT = 45

INTROSPECTION = """
<node>
  <interface name='org.bluez.Agent1'>
    <method name='Release'/>
    <method name='RequestPinCode'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='pincode' direction='out'/>
    </method>
    <method name='DisplayPinCode'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='pincode' direction='in'/>
    </method>
    <method name='RequestPasskey'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='out'/>
    </method>
    <method name='DisplayPasskey'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='in'/>
      <arg type='q' name='entered' direction='in'/>
    </method>
    <method name='RequestConfirmation'>
      <arg type='o' name='device' direction='in'/>
      <arg type='u' name='passkey' direction='in'/>
    </method>
    <method name='RequestAuthorization'>
      <arg type='o' name='device' direction='in'/>
    </method>
    <method name='AuthorizeService'>
      <arg type='o' name='device' direction='in'/>
      <arg type='s' name='uuid' direction='in'/>
    </method>
    <method name='Cancel'/>
  </interface>
</node>
"""

REJECTED = "org.bluez.Error.Rejected"
CANCELED = "org.bluez.Error.Canceled"

log = logging.getLogger("bt-pair-agent")


def device_name(bus, path):
    """Best-effort human name for whatever is asking to pair."""
    try:
        proxy = Gio.DBusProxy.new_sync(
            bus, Gio.DBusProxyFlags.NONE, None,
            "org.bluez", path, "org.freedesktop.DBus.Properties", None,
        )
        for prop in ("Alias", "Name", "Address"):
            value = proxy.call_sync(
                "Get",
                GLib.Variant("(ss)", ("org.bluez.Device1", prop)),
                Gio.DBusCallFlags.NONE, 2000, None,
            )
            name = value.unpack()[0]
            if name:
                return name
    except GLib.Error:
        pass
    return path


def set_trusted(bus, path):
    """Mark a freshly bonded device trusted.

    Without this BlueZ wants authorisation for each incoming connection, and
    since this agent is the only one registered, an unattended reconnect after
    a reboot has nobody to answer -- notifications just stop. Safe to do here:
    the bond it applies to was already gated by the passkey.
    """
    try:
        proxy = Gio.DBusProxy.new_sync(
            bus, Gio.DBusProxyFlags.NONE, None,
            "org.bluez", path, "org.freedesktop.DBus.Properties", None,
        )
        proxy.call_sync(
            "Set",
            GLib.Variant("(ssv)", ("org.bluez.Device1", "Trusted",
                                   GLib.Variant("b", True))),
            Gio.DBusCallFlags.NONE, 2000, None,
        )
        log.info("marked %s trusted", path)
    except GLib.Error as exc:
        log.warning("could not mark %s trusted: %s", path, exc)


def confirm_passkey(name, passkey):
    """Show the code and ask. True only on an explicit Accept.

    swaynag, matching the AirDrop receive prompt: it is part of sway itself so
    it is always present, it draws its own surface, and it needs no
    notification daemon -- notify-send would return success having shown nobody
    anything, which is the worst failure mode for a consent prompt. A terminal
    was used before, but this is the same question the AirDrop prompt asks and
    it should look and answer the same way.

    Fails closed: if there is no session to ask in, or nobody answers, the
    answer is no.
    """
    if not shutil.which("swaynag"):
        log.warning("swaynag not found - refusing (cannot ask, so cannot consent)")
        return False
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("SWAYSOCK")):
        log.warning("no Wayland session visible - refusing (nobody to ask)")
        return False

    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    with tempfile.TemporaryDirectory(dir=runtime) as tmp:
        accept = os.path.join(tmp, "accept")
        decline = os.path.join(tmp, "decline")
        message = (
            f"Pair with {name}?\n"
            f"Code on this machine: {passkey:06d}\n"
            "Accept only if the phone shows the SAME code."
        )
        nag = subprocess.Popen(
            ["swaynag", "--type", "warning", "--message", message,
             "--button-dismiss-no-terminal", "Accept",
             f"/bin/sh -c 'touch \"{accept}\"'",
             "--button-dismiss-no-terminal", "Decline",
             f"/bin/sh -c 'touch \"{decline}\"'"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

        def answered():
            if os.path.exists(accept):
                return True
            if os.path.exists(decline):
                return False
            return None

        # Poll rather than wait on swaynag: --button-dismiss-no-terminal
        # dismisses first and runs the command from a detached child, so
        # swaynag exits *before* the marker is written. Waiting on the process
        # and then testing loses that race every time (it cost an evening in
        # airdrop-confirm), hence the grace period after it goes away.
        deadline = time.monotonic() + CONFIRM_TIMEOUT
        result = None
        while result is None:
            result = answered()
            if result is not None:
                break
            if nag.poll() is not None:
                grace = time.monotonic() + 1.0
                while result is None and time.monotonic() < grace:
                    result = answered()
                    if result is None:
                        time.sleep(0.1)
                break
            if time.monotonic() >= deadline:
                break
            time.sleep(0.1)

        if nag.poll() is None:
            nag.kill()

        if result is None:
            log.info("no answer within %ss - refusing", CONFIRM_TIMEOUT)
            return False
        return result


def notify(title, body, urgency="normal"):
    subprocess.run(
        ["notify-send", "-u", urgency, "-a", "Bluetooth pairing", title, body],
        check=False,
    )


class Agent:
    def __init__(self, bus):
        self.bus = bus

    def handle(self, _conn, _sender, _path, _iface, method, params, invocation):
        log.info("BlueZ called %s", method)
        if method in ("Release", "Cancel"):
            invocation.return_value(None)
            return

        if method == "RequestConfirmation":
            path, passkey = params.unpack()
            self.request_confirmation(path, passkey, invocation)
            return

        if method in ("RequestAuthorization", "AuthorizeService"):
            # Only reached for an already-bonded device asking to use a
            # service. The bond itself was gated by the passkey, so the
            # meaningful check has already happened; refusing here would just
            # break reconnects. Trust the bond -- and record that trust, so
            # later reconnects do not need an agent at all.
            path = params.unpack()[0]
            set_trusted(self.bus, path)
            invocation.return_value(None)
            return

        # Everything else is either legacy pairing (RequestPinCode,
        # DisplayPinCode) or the weaker methods we deliberately do not offer
        # (RequestConfirmation, DisplayPasskey). Refusing them is what stops a
        # remote device negotiating its way down to a one-click bond.
        invocation.return_dbus_error(
            REJECTED, f"{method} is not accepted; passkey entry is required")

    def request_confirmation(self, path, passkey, invocation):
        name = device_name(self.bus, path)

        def worker():
            if confirm_passkey(name, passkey):
                log.info("accepted pairing with %s", name)
                invocation.return_value(None)
            else:
                log.info("refused pairing with %s", name)
                invocation.return_dbus_error(REJECTED, "not confirmed")
                notify("Pairing refused", f"{name} was not paired.", "critical")

        # Off the main loop: BlueZ is waiting on this call and the GLib loop
        # still has to service the bus while the prompt is open.
        threading.Thread(target=worker, daemon=True).start()


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    agent = Agent(bus)
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    bus.register_object(AGENT_PATH, node.interfaces[0], agent.handle, None, None)

    manager = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None,
        "org.bluez", "/org/bluez", "org.bluez.AgentManager1", None,
    )
    manager.call_sync(
        "RegisterAgent", GLib.Variant("(os)", (AGENT_PATH, CAPABILITY)),
        Gio.DBusCallFlags.NONE, 5000, None,
    )

    # Becoming the default agent is what actually displaces blueman's, and the
    # last caller wins. sway starts blueman-applet and this script with no
    # ordering between them, and blueman re-registers whenever it restarts, so
    # claiming once would be a race we sometimes lose -- and losing it silently
    # downgrades pairing back to a one-click dialog. Re-assert on a timer.
    def claim_default():
        try:
            manager.call_sync(
                "RequestDefaultAgent", GLib.Variant("(o)", (AGENT_PATH,)),
                Gio.DBusCallFlags.NONE, 5000, None,
            )
        except GLib.Error as exc:
            print(f"could not become default agent: {exc}", file=sys.stderr)
        return True

    claim_default()
    GLib.timeout_add_seconds(30, claim_default)

    print("passkey pairing agent registered", flush=True)
    GLib.MainLoop().run()


if __name__ == "__main__":
    try:
        main()
    except GLib.Error as exc:
        print(f"failed to register agent: {exc}", file=sys.stderr)
        sys.exit(1)
