#!/bin/sh
# touchpad-resume-fix.sh - re-probe the I2C-HID touchpad so it recovers after
# resume. Without this the touchpad wakes up wedged on this machine: either the
# cursor is frozen outright, or it only twitches / refuses to move while clicks
# still register. The touchscreen is on a separate controller and is unaffected.
#
# Called by elogind as a system-sleep hook:  $1 = pre|post, $2 = suspend|...
# Only acts on the post-resume call. Safe to run by hand with no args, and
# bound to $mod+Shift+r in sway/config as a manual "unstick the touchpad" key.
set -eu

# Only run on resume. elogind passes "post" after waking; an empty $1
# (manual invocation) also proceeds.
case "${1:-post}" in
	post|"") ;;
	*) exit 0 ;;
esac

DEV="AMDI0010:03"
DRV="/sys/bus/platform/drivers/i2c_designware"

HID_DEV="i2c-CRQ1080:00"
HID_DRV="/sys/bus/i2c/drivers/i2c_hid_acpi"

# The touchpad has two distinct failure modes, so try the cheap fix first.
#
# 1. The device re-enumerates but hid-multitouch never gets it out of its
#    degenerate mode: it streams bare coordinates (ABS_X/Y, ABS_MT_POSITION_X/Y)
#    with no BTN_TOUCH and no ABS_MT_TRACKING_ID. libinput won't synthesise
#    motion from a touchpad that never reports a finger down, so the cursor
#    sits still while physical clicks (BTN_LEFT) still work. Rebinding at the
#    i2c_hid level re-probes the HID device and re-sends the mode-switch
#    feature report. Check with:
#      sudo libinput debug-events --device /dev/input/eventN
#
# 2. The AMD I2C controller itself is dead after resume, in which case the
#    i2c_hid rebind fails with "No such device" and you have to reset one
#    level up at the i2c_designware platform driver.
if [ -d "$HID_DRV" ] && [ -e "$HID_DRV/$HID_DEV" ]; then
	printf '%s' "$HID_DEV" > "$HID_DRV/unbind" 2>/dev/null || true
	sleep 1
	printf '%s' "$HID_DEV" > "$HID_DRV/bind" 2>/dev/null || true
	# Recovered if the HID device came back on the bus.
	[ -e "$HID_DRV/$HID_DEV" ] && exit 0
fi

# Nothing more to do if the controller or driver isn't present on this kernel.
[ -d "$DRV" ] || exit 0
[ -e "/sys/bus/platform/devices/$DEV" ] || exit 0

# Rebind: power-cycles the I2C bus and re-probes the touchpad child device.
printf '%s' "$DEV" > "$DRV/unbind" 2>/dev/null || true
sleep 1
printf '%s' "$DEV" > "$DRV/bind" 2>/dev/null || true
