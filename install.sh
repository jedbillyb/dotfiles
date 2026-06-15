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
		mv "$target" "$target.bak"
		info "backup $target -> $target.bak"
	fi
	ln -s "$src" "$target"
	info "link  $target"
}

echo "Installing dotfiles from $REPO"

echo "Configs:"
link sway/config   "$CONFIG/sway/config"
link i3/config     "$CONFIG/i3/config"
link waybar        "$CONFIG/waybar"
link wofi/config   "$CONFIG/wofi/config"

echo "Scripts (-> $BIN):"
mkdir -p "$BIN"
for s in vpn-toggle.sh caffeine-toggle.sh sway-idle.sh openclaw-send; do
	chmod +x "$REPO/scripts/$s"
	link "scripts/$s" "$BIN/$s"
done
# Waybar status scripts run from the repo via the symlinked config dir;
# just make sure they are executable.
chmod +x "$REPO"/waybar/*.sh

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
