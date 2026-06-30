#!/bin/sh
# touchpad-resume-fix.sh - rebind the AMD I2C controller after resume so the
# I2C-HID touchpad recovers. Without this the touchpad wakes up wedged
# (cursor frozen, only twitches) on this machine; the touchscreen is on a
# separate controller and is unaffected.
#
# Called by elogind as a system-sleep hook:  $1 = pre|post, $2 = suspend|...
# Only acts on the post-resume call. Safe to run by hand with no args.
set -eu

# Only run on resume. elogind passes "post" after waking; an empty $1
# (manual invocation) also proceeds.
case "${1:-post}" in
	post|"") ;;
	*) exit 0 ;;
esac

DEV="AMDI0010:03"
DRV="/sys/bus/platform/drivers/i2c_designware"

# Nothing to do if the controller or driver isn't present on this kernel.
[ -d "$DRV" ] || exit 0
[ -e "/sys/bus/platform/devices/$DEV" ] || exit 0

# Rebind: power-cycles the I2C bus and re-probes the touchpad child device.
printf '%s' "$DEV" > "$DRV/unbind" 2>/dev/null || true
sleep 1
printf '%s' "$DEV" > "$DRV/bind" 2>/dev/null || true
