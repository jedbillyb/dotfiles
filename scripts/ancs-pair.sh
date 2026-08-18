#!/bin/sh
# Prepare this machine for a deliberate iPhone (ANCS) pairing.
#
# Deliberately does NOT call `ancs4linux-ctl enable-pairing`. That registers
# ancs4linux's own agent as the system default, and its RequestConfirmation is:
#
#     def RequestConfirmation(self, device, passkey) -> None:
#         self.server.emit_pairing_code(str(int(passkey)))
#
# Returning from RequestConfirmation is how BlueZ is told the user consented;
# rejecting means raising. So it shows you a code and accepts no matter what.
# The code always "matches" because nothing ever compares it, and the prompt is
# decorative -- anyone in range who taps pair gets bonded. This script instead
# makes sure that agent is *off* and leaves pairing to blueman-applet's agent,
# which shows a real confirmation dialog and honours the answer.
set -eu

CTL=/mnt/shared/projects/ancs4linux/.venv/bin/ancs4linux-ctl

# Belt and braces: enabling advertising auto-registers the bad agent, so make
# sure a restart in the last few seconds has not left it registered.
[ -x "$CTL" ] && "$CTL" disable-pairing >/dev/null 2>&1 || true

if ! pgrep -x blueman-applet >/dev/null 2>&1; then
	echo "WARNING: blueman-applet is not running, so no pairing agent is" >&2
	echo "registered and the pair will fail. Start it first." >&2
	exit 1
fi

bluetoothctl pairable on >/dev/null 2>&1 || true
bluetoothctl discoverable on >/dev/null 2>&1 || true

cat <<'MSG'
Ready to pair.

  On the iPhone: Settings > Bluetooth
    1. Forget any old entry for this machine (JedLinux / void-btw).
    2. Tap "Jeds Linux Laptop" under Other Devices.
    3. blueman will pop a dialog here showing a 6-digit code. Compare it with
       the one on the phone and only accept if they match -- this one is real.
MSG
