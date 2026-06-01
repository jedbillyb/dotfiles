# dotfiles

My personal configuration files.

## Contents

- `sway/config` - Sway window manager config
- `i3/config` - i3 window manager config (legacy)
- `scripts/vpn-toggle.sh` - WireGuard VPN toggle (bound to mod+v)
- `scripts/openclaw-send` - openclaw helper script
- `wireguard/wg0.conf.template` - WireGuard client config template (fill in private key)

## Usage

```sh
git clone https://github.com/jedbillyb/dotfiles ~/projects/dotfiles

ln -s ~/projects/dotfiles/sway/config ~/.config/sway/config

# WireGuard: copy template, fill in PrivateKey and assign an IP
sudo cp ~/projects/dotfiles/wireguard/wg0.conf.template /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# Scripts
ln -s ~/projects/dotfiles/scripts/vpn-toggle.sh ~/.local/bin/vpn-toggle.sh
ln -s ~/projects/dotfiles/scripts/openclaw-send ~/.local/bin/openclaw-send
```
