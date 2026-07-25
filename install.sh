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

echo "Shell + git (-> \$HOME):"
link shell/bashrc       "$HOME/.bashrc"
link shell/zshrc        "$HOME/.zshrc"
link shell/bash_profile "$HOME/.bash_profile"
link shell/profile      "$HOME/.profile"
link shell/inputrc      "$HOME/.inputrc"
link git/gitconfig      "$HOME/.gitconfig"

echo "Scripts (-> $BIN):"
mkdir -p "$BIN"
for s in vpn-toggle.sh caffeine-toggle.sh sway-idle.sh sway-lock.sh waybar-run.sh openclaw-send wifi-compare.sh; do
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
if [ -e "$WG_CONF" ]; then
	info "skip  $WG_CONF already exists (left untouched)"
else
	info "copying template -> $WG_CONF (fill in PrivateKey + IP)"
	sudo cp "$REPO/wireguard/wg0.conf.template" "$WG_CONF"
	sudo chmod 600 "$WG_CONF"
fi

cat <<EOF

Done. Manual steps not handled here (see README):
  - WireGuard: edit $WG_CONF with your PrivateKey and IP
  - VPN passwordless sudo rule (/etc/sudoers.d/zz-wg-toggle)
  - swaylock-fprintd build + PAM setup for the lock screen
Make sure "$BIN" is on your PATH.
EOF
