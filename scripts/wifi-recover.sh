#!/bin/bash
# Force Wi-Fi back to a known-good state, covering every way AirDrop/AWDL
# testing (owl, airdrop-mt7921, mt7921-dual-channel) can leave it broken:
# leftover monitor/P2P-GO vifs, a stranded awdl0, hostapd still running, mt76
# runtime-pm/deep-sleep left disabled, rfkill soft-blocked, the regulatory
# domain left where a run put it, the interface taken down by hand or left in
# monitor type ("THE WORKING RECIPE"), NetworkManager or avahi-daemon still
# stopped by an airdrop.sh run that never hit its exit trap, or NetworkManager
# left unmanaging/disconnected. Bound alongside the touchpad-resume fix on
# $mod+Shift+r so one keybinding recovers from any post-suspend/post-testing
# mess.
#
# Three layers, cheapest first, and every step is conditional - this fires on
# every $mod+Shift+r, including plain config reloads with nothing wrong, so it
# must never bounce a healthy association:
#
#   1. sudo/airdrop-helper - the radio itself (vifs, mt76 power management,
#      rfkill, interface up). Root-owned, NOPASSWD, fixed verb; see that
#      script's header for why nothing here is allowed to sudo iw/ip directly.
#      It lives in the airdrop-mt7921 repo and is left alone.
#   2. sudo/wifi-recover-root - everything privileged that airdrop-helper does
#      not cover (repo-name owl, awdl0, reg domain, monitor-type interface,
#      stopped services). Same pattern, this repo's own script.
#   3. nmcli, as the desktop user - undo the NetworkManager-level state.
#
# Layers 1 and 2 no-op silently if their sudoers rules are not installed, so
# the nmcli half still runs on a machine that has never done AirDrop testing.

IFACE=wlp2s0

sudo -n /usr/local/bin/airdrop-helper wifi-reset 2>/dev/null
sudo -n /usr/local/bin/airdrop-helper avahi-up 2>/dev/null
sudo -n /usr/local/bin/wifi-recover-root 2>/dev/null

# NetworkManager may have just been started by layer 2; give it a moment to
# take the D-Bus name, or the nmcli calls below hit "not running" and the
# recovery quietly does nothing.
for _ in 1 2 3 4 5 6 7 8 9 10; do
	nmcli general status >/dev/null 2>&1 && break
	sleep 0.5
done

nmcli radio wifi on 2>/dev/null
nmcli networking on 2>/dev/null
nmcli device set "$IFACE" managed yes 2>/dev/null
nmcli connection modify 2142-WiFi connection.autoconnect yes 2>/dev/null

# Only force a (re)connect if it's not already connected - an unconditional
# `nmcli device connect` bounces a healthy association.
#
# The line is `GENERAL.STATE:100 (connected)`, so the state is field 2 and
# carries the text as well as the number. Reading field 1 (the key) instead
# meant this test never matched and every $mod+Shift+r dropped a working link
# for a second or two.
state=$(nmcli -t -f GENERAL.STATE device show "$IFACE" 2>/dev/null | cut -d: -f2)
case "$state" in
100*) ;;
*) nmcli device connect "$IFACE" 2>/dev/null ;;
esac

exit 0
