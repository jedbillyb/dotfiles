#!/usr/bin/env python3
"""Bluetooth pairing agent that makes you type the passkey on this laptop.

Replaces both agents that would otherwise handle pairing here:

  * ancs4linux's, whose RequestConfirmation emits the passkey as a notification
    and returns -- and returning is how BlueZ is told the user consented. It
    accepts every bond, so a stranger only had to tap "Pair" on their own
    device. The code it showed was never compared to anything, so it was always
    "right".
  * blueman's, which does ask, but only with a yes/no dialog. Numeric
    comparison is only as strong as the person reading it, and a dialog that
    can be dismissed with one click is one click from a bond.

So this agent advertises KeyboardOnly, which makes BlueZ negotiate Passkey
Entry instead of Numeric Comparison: the phone *displays* a six-digit code and
this laptop *asks for it*. Consent now requires knowing a number shown on the
other device, which someone pairing from across the room cannot supply -- there
is no button to click blindly.

Runs as your user from the sway session so it can put the prompt on screen.
Registering a BlueZ agent as an unprivileged user is allowed; blueman does the
same.
"""

import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

AGENT_PATH = "/org/jedbillyb/BtPairAgent"

# KeyboardOnly is the whole point: against a phone (DisplayYesNo) it forces
# Passkey Entry with the phone displaying and us entering. DisplayYesNo would
# get us Numeric Comparison and a one-click dialog instead.
CAPABILITY = "KeyboardOnly"

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


def ask_passkey(name):
    """Put a prompt on screen and return what was typed, or None if dismissed.

    wofi in dmenu mode with no options behaves as a plain text entry. Escape
    exits non-zero, which is how a refusal reaches us.
    """
    try:
        result = subprocess.run(
            ["wofi", "--dmenu", "--lines", "1", "--width", "460",
             "--prompt", f"Passkey shown on {name}"],
            input="", capture_output=True, text=True, timeout=90,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def notify(title, body, urgency="normal"):
    subprocess.run(
        ["notify-send", "-u", urgency, "-a", "Bluetooth pairing", title, body],
        check=False,
    )


class Agent:
    def __init__(self, bus):
        self.bus = bus

    def handle(self, _conn, _sender, _path, _iface, method, params, invocation):
        if method in ("Release", "Cancel"):
            invocation.return_value(None)
            return

        if method == "RequestPasskey":
            (path,) = params.unpack()
            self.request_passkey(path, invocation)
            return

        if method in ("RequestAuthorization", "AuthorizeService"):
            # Only reached for an already-bonded device asking to use a
            # service. The bond itself was gated by the passkey, so the
            # meaningful check has already happened; refusing here would just
            # break reconnects. Trust the bond.
            invocation.return_value(None)
            return

        # Everything else is either legacy pairing (RequestPinCode,
        # DisplayPinCode) or the weaker methods we deliberately do not offer
        # (RequestConfirmation, DisplayPasskey). Refusing them is what stops a
        # remote device negotiating its way down to a one-click bond.
        invocation.return_dbus_error(
            REJECTED, f"{method} is not accepted; passkey entry is required")

    def request_passkey(self, path, invocation):
        name = device_name(self.bus, path)
        notify("Pairing request", f"{name} wants to pair. Type the code it is "
                                  "showing.")

        typed = ask_passkey(name)
        if typed is None:
            invocation.return_dbus_error(CANCELED, "passkey entry dismissed")
            notify("Pairing refused", f"{name} was not paired.", "critical")
            return

        digits = "".join(c for c in typed if c.isdigit())
        if not digits:
            invocation.return_dbus_error(REJECTED, "no passkey entered")
            notify("Pairing refused", "No code was entered.", "critical")
            return

        # BlueZ wants the passkey as a number. A leading zero is significant
        # to the user but not to int(), which is fine -- 012345 and 12345 are
        # the same value on the wire.
        invocation.return_value(GLib.Variant("(u)", (int(digits),)))


def main():
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
