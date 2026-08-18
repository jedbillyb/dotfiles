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
# rejecting means raising. So it shows a code and accepts regardless -- the code
# is always "right" because nothing compares it, and a stranger only has to tap
# Pair on their own device.
#
# bt-pair-agent.py handles pairing instead, advertising KeyboardOnly so BlueZ
# negotiates Passkey Entry: the phone displays a code and you type it here.
set -eu

CTL=/mnt/shared/projects/ancs4linux/.venv/bin/ancs4linux-ctl
AGENT=bt-pair-agent

# Enabling advertising auto-registers ancs4linux's agent, so make sure a
# restart in the last few seconds has not left it registered.
[ -x "$CTL" ] && "$CTL" disable-pairing >/dev/null 2>&1 || true

# pgrep -f would match this script's own command line, so look at the python
# processes directly.
running=0
for pid in $(pgrep -x python3 2>/dev/null); do
	if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "$AGENT"; then
		running=1
		break
	fi
done

if [ "$running" = 0 ]; then
	echo "WARNING: $AGENT.py is not running, so pairing would fall through to" >&2
	echo "blueman's one-click dialog, or fail outright. Start it first." >&2
	exit 1
fi

bluetoothctl pairable on >/dev/null 2>&1 || true
bluetoothctl discoverable on >/dev/null 2>&1 || true

cat <<'MSG'
Ready to pair.

  On the iPhone: Settings > Bluetooth
    1. Forget any old entry for this machine (JedLinux / void-btw).
    2. Tap "Jeds Linux Laptop" under Other Devices.
    3. The phone shows a six-digit code and a prompt appears here.
       Type the phone's code into it.
MSG
