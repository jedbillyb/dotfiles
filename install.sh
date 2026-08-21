#!/bin/sh
# install.sh - symlink dotfiles into place and set up scripts.
# Idempotent: re-running is safe. Existing real files are backed up to
# <file>.bak before being replaced with a symlink.
set -eu

# Absolute path to this repo, regardless of where the script is called from.
REPO="$(cd "$(dirname "$0")" && pwd)"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN="$HOME/.local/bin"

info() { printf '  %s\n' "$1"; }

# link SRC TARGET - symlink REPO/SRC -> TARGET, backing up a real file first.
link() {
	src="$REPO/$1"
	target="$2"
	mkdir -p "$(dirname "$target")"
	# Already the correct symlink? Nothing to do.
	if [ -L "$target" ] && [ "$(readlink "$target")" = "$src" ]; then
		info "ok    $target"
		return
	fi
	# A real file/dir (or wrong link) is in the way - back it up.
	if [ -e "$target" ] || [ -L "$target" ]; then
		backup="$target.bak"
		# Don't clobber an existing backup; fall back to a timestamped name.
		if [ -e "$backup" ] || [ -L "$backup" ]; then
			backup="$target.bak.$(date +%Y%m%d%H%M%S)"
		fi
		mv "$target" "$backup"
		info "backup $target -> $backup"
	fi
	ln -s "$src" "$target"
	info "link  $target"
}

echo "Installing dotfiles from $REPO"

echo "Packages:"
# autotiling powers the spiral/dwindle layout (exec_always in sway/config).
if command -v autotiling >/dev/null 2>&1; then
	info "ok    autotiling"
else
	info "installing autotiling"
	sudo xbps-install -y autotiling
fi

echo "Configs:"
link sway/config   "$CONFIG/sway/config"
link i3/config     "$CONFIG/i3/config"
link waybar        "$CONFIG/waybar"
link wofi/config    "$CONFIG/wofi/config"
link wofi/style.css "$CONFIG/wofi/style.css"
link foot/foot.ini "$CONFIG/foot/foot.ini"
link xdg-desktop-portal/sway-portals.conf "$CONFIG/xdg-desktop-portal/sway-portals.conf"
link xdg-desktop-portal/portals.conf      "$CONFIG/xdg-desktop-portal/portals.conf"
link xdg-desktop-portal-wlr/config        "$CONFIG/xdg-desktop-portal-wlr/config"
link airdrop/config "$CONFIG/airdrop/config"
# Bluetooth sink roles off: the iPhone is paired for notifications, not audio.
link wireplumber/wireplumber.conf.d "$CONFIG/wireplumber/wireplumber.conf.d"

echo "Shell + git (-> \$HOME):"
link emptty/emptty      "$CONFIG/emptty"

link shell/bashrc       "$HOME/.bashrc"
link shell/zshrc        "$HOME/.zshrc"
link shell/bash_profile "$HOME/.bash_profile"
link shell/profile      "$HOME/.profile"
link shell/inputrc      "$HOME/.inputrc"
link git/gitconfig      "$HOME/.gitconfig"

echo "Scripts (-> $BIN):"
mkdir -p "$BIN"
# Everything in scripts/ that belongs in $BIN. touchpad-resume-fix.sh and
# wifi-recover-root.sh are deliberately absent: they are installed elsewhere
# below, into the elogind hook directory and /usr/local/bin respectively.
for s in vpn-toggle.sh vpn-proxy.sh vpn-wstunnel.sh caffeine-toggle.sh show-desktop.sh sway-idle.sh sway-lock.sh waybar-run.sh waybar-toggle.sh openclaw-send wifi-compare.sh wifi-recover.sh touch-gestures.sh touch-resize.sh touch-resized.py workspace-step.py wofi-dismiss.py wofi-backdrop.py touch-shield.py zed-wrapper; do
	chmod +x "$REPO/scripts/$s"
	link "scripts/$s" "$BIN/$s"
done
# Standalone launchers living in bin/ (e.g. the Spotlight-style wofi wrapper).
for b in spotlight; do
	chmod +x "$REPO/bin/$b"
	link "bin/$b" "$BIN/$b"
done
# Waybar status scripts run from the repo via the symlinked config dir;
# just make sure they are executable.
chmod +x "$REPO"/waybar/*.sh

echo "Privileged Wi-Fi recovery helper:"
# Installed as a root-owned COPY, not a symlink: it runs as root from the
# $mod+Shift+r keybinding, and a symlink back into this repo would make
# anything able to write the repo able to run code as root. The copy is
# unconditional so it tracks changes to the script. The matching sudoers rule
# is a manual step (see README), like the wg-quick one.
WIFI_ROOT="/usr/local/bin/wifi-recover-root"
sudo install -o root -g root -m 755 "$REPO/scripts/wifi-recover-root.sh" "$WIFI_ROOT"
info "copy  $WIFI_ROOT"

echo "Touchscreen gestures (udev + input group):"
# Copy, not symlink: udev reads its rules very early and before /mnt is
# necessarily mounted, so a rule that lives in this repo would be missing on
# some boots.
TOUCH_RULE="/etc/udev/rules.d/99-touchscreen-lisgd.rules"
sudo install -o root -g root -m 644 "$REPO/udev/99-touchscreen-lisgd.rules" "$TOUCH_RULE"
info "copy  $TOUCH_RULE"
sudo udevadm control --reload-rules
# Scoped to the touchscreen deliberately. Re-triggering every input device also
# hits the I2C-HID touchpad, which has a history of wedging on re-enumeration
# (see "Touchpad wedges after resume").
sudo udevadm trigger --subsystem-match=input --action=change \
	--property-match=ID_INPUT_TOUCHSCREEN=1
# lisgd itself is built by hand from a checkout, not by this script, and it needs
# four local patches (see "Keeping the patches applied" in the README). Losing
# them is silent -- gestures keep half-working and start eating one another --
# so at least say so here. Each patch adds a string the stock binary lacks;
# cardinals-before-diagonals only reorders code and cannot be detected this way.
LISGD_BIN="$BIN/lisgd"
if [ ! -x "$LISGD_BIN" ]; then
	info "warn  no lisgd at $LISGD_BIN; touch gestures will not start"
else
	for probe in LISGD_CUR_X "Pressed gesture declined" "/px=%.0f"; do
		if ! grep -qa "$probe" "$LISGD_BIN"; then
			info "warn  $LISGD_BIN looks unpatched (no '$probe') -- see README"
		fi
	done
fi

if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
	info "ok    $USER already in the input group"
else
	sudo usermod -aG input "$USER"
	info "group $USER added to input (takes effect at next login; the script
       bridges the gap with sg until then)"
fi

echo "Resume hooks (elogind system-sleep):"
SLEEP_HOOK="/usr/libexec/elogind/system-sleep/touchpad-resume-fix.sh"
chmod +x "$REPO/scripts/touchpad-resume-fix.sh"
if [ -L "$SLEEP_HOOK" ] && [ "$(readlink "$SLEEP_HOOK")" = "$REPO/scripts/touchpad-resume-fix.sh" ]; then
	info "ok    $SLEEP_HOOK"
else
	sudo mkdir -p "$(dirname "$SLEEP_HOOK")"
	sudo ln -sf "$REPO/scripts/touchpad-resume-fix.sh" "$SLEEP_HOOK"
	info "link  $SLEEP_HOOK"
fi

echo "WireGuard:"
WG_CONF="/etc/wireguard/wg0.conf"
# Test as root, not as $USER: /etc/wireguard is 0700 root:root, so an
# unprivileged [ -e ] cannot traverse it and reports "missing" even when the
# file is there. That silently sent every run down the copy path below and
# overwrote a working config with the placeholder template.
if sudo test -e "$WG_CONF"; then
	info "skip  $WG_CONF already exists (left untouched)"
else
	info "copying template -> $WG_CONF (fill in PrivateKey + IP)"
	sudo cp "$REPO/wireguard/wg0.conf.template" "$WG_CONF"
	sudo chmod 600 "$WG_CONF"
fi

echo "iPhone notifications (ANCS):"
# dunst is the notification server sway/config execs; without it ANCS
# notifications arrive on the bus and go nowhere.
if command -v dunst >/dev/null 2>&1; then
	info "ok    dunst"
else
	info "installing dunst"
	sudo xbps-install -y dunst
fi
# Copy, not symlink: runit reads /etc/sv at boot, long before /mnt/shared is
# mounted. The run scripts themselves wait for /mnt before exec'ing.
for svc in ancs4linux-observer ancs4linux-advertising ancs4linux-reconnect ancs4linux-watchdog; do
	sudo mkdir -p "/etc/sv/$svc"
	sudo install -o root -g root -m 755 "$REPO/ancs4linux/sv/$svc/run" "/etc/sv/$svc/run"
	sudo mkdir -p "/etc/sv/$svc/log" "/var/log/$svc"
	sudo install -o root -g root -m 755 "$REPO/ancs4linux/sv/$svc/log/run" "/etc/sv/$svc/log/run"
	sudo ln -sfn "/etc/sv/$svc" "/var/service/$svc"
	info "copy  /etc/sv/$svc"
done
# The daemons own system-bus names restricted to root and this group; the
# desktop-integration half runs as you and needs to talk to them.
sudo groupadd -f ancs4linux
sudo usermod -a -G ancs4linux "$USER"
for cfg in observer advertising; do
	sudo install -o root -g root -m 644 \
		"/mnt/shared/projects/ancs4linux/autorun/ancs4linux-$cfg.xml" \
		"/etc/dbus-1/system.d/ancs4linux-$cfg.conf"
done
info "copy  /etc/dbus-1/system.d/ancs4linux-*.conf"

# What the iPhone shows in its Bluetooth list. BlueZ otherwise falls back to
# the hostname ("void-btw"), which is meaningless on the phone. The BLE
# advertising name is set separately, in the advertising run script.
sudo bluetoothctl system-alias "Jeds Linux Laptop" >/dev/null 2>&1 || true
info "alias Jeds Linux Laptop"
# Stay discoverable and pairable indefinitely so any device can be paired at
# any time, and so the phone can be forgotten and re-paired to test. Both
# timeouts are non-zero by default, which drops the machine off other devices'
# lists minutes after boot. Safe because bt-pair-agent.py gates every pairing
# behind a passkey typed here. The advertising service sets these at runtime
# too; this makes them stick even if that service is not running.
sudo sed -i \
	-e 's/^#\?DiscoverableTimeout = .*/DiscoverableTimeout = 0/' \
	-e 's/^#\?PairableTimeout = .*/PairableTimeout = 0/' \
	-e 's/^#\?AlwaysPairable = .*/AlwaysPairable = true/' \
	/etc/bluetooth/main.conf
info "edit  /etc/bluetooth/main.conf (always discoverable + pairable)"
link dunst/dunstrc "$CONFIG/dunst/dunstrc"
link scripts/ancs-pair.sh "$BIN/ancs-pair.sh"

cat <<EOF

Done. Manual steps not handled here (see README):
  - WireGuard: edit $WG_CONF with your PrivateKey and IP
  - VPN passwordless sudo rule (/etc/sudoers.d/zz-wg-toggle)
  - Wi-Fi recovery passwordless sudo rule (/etc/sudoers.d/zz-wifi-recover)
  - swaylock-fprintd build + PAM setup for the lock screen
  - ANCS: clone pzmarzly/ancs4linux to /mnt/shared/projects and build its
    venv, then pair the iPhone fresh (see README)
Make sure "$BIN" is on your PATH.
EOF
