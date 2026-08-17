#!/bin/sh
# Privileged half of the $mod+Shift+r Wi-Fi recovery. Takes no arguments and
# does one fixed thing, so the NOPASSWD rule that lets a keybinding run it
# grants exactly this and nothing else - the same reasoning as airdrop-helper.
# It is installed as a root-owned COPY in /usr/local/bin, never symlinked back
# into this repo: running a user-writable file as root would hand root to
# anything able to write the repo.
#
# It covers only what `airdrop-helper wifi-reset` does NOT, so the two compose
# rather than duplicate. That script owns the radio itself (monitor/GO vifs,
# mt76 runtime-pm and deep-sleep, rfkill, bringing the managed interface up).
# What was still left broken after an interrupted AirDrop/AWDL session, and is
# handled here:
#
#   - owl running under its repo name. airdrop.sh runs ~/owl/build/daemon/owl,
#     so the process is `owl`; airdrop-helper only kills the installed
#     `airdrop-owl`. A surviving owl keeps reasserting awdl0 underneath the
#     rest of the recovery.
#   - a leftover awdl0. owl removes its own tun on a clean exit, but the hung
#     or -9'd owl that makes you reach for this keybinding does not.
#   - the regulatory domain. airdrop.sh sets it per run for injection and never
#     restores it, so it silently stays wherever the last run left it.
#   - the managed interface stuck in monitor type. A run interrupted between
#     `iw dev <iface> set type monitor` and its restore leaves it there, and
#     then nothing NetworkManager does can associate.
#   - mt76 power management when debugfs is not mounted. airdrop-helper mounts
#     debugfs in `up` but not in `wifi-reset`, so a reset after a reboot (or
#     after anything unmounted it) fails both knob writes with "No such file or
#     directory" and silently leaves runtime-pm/deep-sleep disabled - which
#     costs battery and adds latency with no visible symptom.
#   - an rfkill soft block, when layer 1 is not installed. airdrop-helper does
#     unblock, but it lives in the airdrop-mt7921 repo, so on a machine without
#     it nothing clears a block. The usual cause here has nothing to do with
#     AirDrop anyway: ideapad_laptop registers its own `ideapad_wlan` switch
#     alongside the mt7921's `phy0`, and blocks are OR'd across rfkill devices,
#     so an Fn/airplane key event or a stale EC state after resume soft-blocks
#     the platform switch and takes a perfectly healthy radio down with it.
#     `unblock wifi` covers both devices; bluetooth is deliberately left alone.
#   - NetworkManager or avahi-daemon still stopped. airdrop.sh takes both down
#     for the duration of a run and restores them from an exit trap that a hard
#     kill skips. With NetworkManager down every nmcli call in the caller fails
#     silently, which presents as "Wi-Fi is dead" with no visible cause.
#
# This fires on every $mod+Shift+r, including plain config reloads with nothing
# wrong, so each step is conditional: nothing here touches a healthy link.

[ "$(id -u)" = "0" ] || { echo "wifi-recover-root: must run as root" >&2; exit 1; }

REG=NZ
VIFS="mon0 mon1 go0"

pkill -x owl 2>/dev/null

ip link show awdl0 >/dev/null 2>&1 && ip link del awdl0 2>/dev/null

# Clear a wifi soft block before anything below tries to bring the interface
# up - a blocked phy0 refuses the link-up and the whole recovery no-ops. Only
# when something is actually blocked, so a healthy radio is never touched.
rfkill list wifi 2>/dev/null | grep -q 'blocked: yes' && rfkill unblock wifi 2>/dev/null

# Restore mt76 power management, mounting debugfs first if it isn't - the knobs
# only exist under it. Writing 1 is what "on" means for both.
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
for mt76 in /sys/kernel/debug/ieee80211/phy*/mt76; do
	[ -d "$mt76" ] || continue
	echo 1 > "$mt76/runtime-pm" 2>/dev/null
	echo 1 > "$mt76/deep-sleep" 2>/dev/null
done

[ "$(iw reg get 2>/dev/null | awk '/^country/{print $2; exit}' | tr -d ':')" = "$REG" ] \
	|| iw reg set "$REG" 2>/dev/null

# Any mt7921 netdev that is not one of the AirDrop vifs is the real interface.
# It is looked up here rather than passed in for the same reason airdrop-helper
# resolves it internally: a caller that could name the interface could name
# anything.
for d in /sys/class/net/*/device/driver; do
	[ -e "$d" ] || continue
	case "$(basename "$(readlink -f "$d")")" in
	mt7921*) ;;
	*) continue ;;
	esac
	iface=$(basename "$(dirname "$(dirname "$d")")")
	skip=0
	for v in $VIFS; do
		[ "$iface" = "$v" ] && skip=1
	done
	[ "$skip" = "1" ] && continue

	# A type change needs the link down first, so only do it when the type is
	# actually wrong - otherwise this would bounce a working association.
	if [ "$(iw dev "$iface" info 2>/dev/null | awk '/^\ttype /{print $2}')" != "managed" ]; then
		ip link set "$iface" down 2>/dev/null
		iw dev "$iface" set type managed 2>/dev/null
		ip link set "$iface" up 2>/dev/null
	fi
done

for svc in NetworkManager avahi-daemon; do
	pgrep -x "$svc" >/dev/null 2>&1 && continue
	sv up "$svc" >/dev/null 2>&1 || systemctl start "$svc" >/dev/null 2>&1
done

exit 0
