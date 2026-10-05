#!/bin/sh
# sleep-quiet-fans.sh - drop the platform profile to low-power while asleep,
# then put the previous one back on wake.
#
# This laptop only has s2idle (no S3), and the embedded controller keeps
# running its own fan loop the whole time it is asleep. Under the
# "performance" profile that loop cools aggressively, so with the lid shut the
# fan kicks on and off for hours even though the CPU is in hardware sleep 100%
# of the time (checked: /sys/kernel/debug/amd_pmc/s0ix_stats residency matched
# the full time suspended). low-power gives the EC its quiet curve.
#
# Called by elogind as a system-sleep hook:  $1 = pre|post, $2 = suspend|...
set -eu

PROFILE=/sys/firmware/acpi/platform_profile
SAVED=/run/sleep-quiet-fans.profile

[ -w "$PROFILE" ] || exit 0

case "${1:-}" in
	pre)
		cat "$PROFILE" > "$SAVED"
		echo low-power > "$PROFILE"
		;;
	post)
		[ -f "$SAVED" ] || exit 0
		cat "$SAVED" > "$PROFILE"
		rm -f "$SAVED"
		;;
esac
