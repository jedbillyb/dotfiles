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

## Sway keybindings

`$mod` = **Super** (Mod4, the Windows key).

### Applications

| Keybind | Action |
| --- | --- |
| `$mod+Return` | Terminal (footclient) |
| `$mod+r` | App launcher (wofi) |
| `$mod+f` | Firefox |
| `$mod+p` | File manager (Thunar) |

### System / session

| Keybind | Action |
| --- | --- |
| `$mod+v` | Toggle WireGuard VPN |
| `$mod+Shift+i` | Lock screen (swaylock-fprintd, auto fingerprint) |
| `$mod+Shift+o` | Exit sway, back to TTY |
| `$mod+Shift+p` | Power off |
| `$mod+Shift+r` | Reload sway config |

### Window management

| Keybind | Action |
| --- | --- |
| `$mod+q` | Close window |
| `$mod+h` | Split horizontal |
| `$mod+s` | Stacking layout |
| `$mod+w` | Tabbed layout |
| `$mod+e` | Toggle split layout |
| `$mod+Shift+f` | Toggle fullscreen |
| `$mod+Shift+space` | Toggle floating |
| `$mod+space` | Toggle focus tiling/floating |
| `$mod+a` | Focus parent |
| `$mod+Shift+d` | Enter resize mode |

### Focus / move

| Keybind | Action |
| --- | --- |
| `$mod+j` / `k` / `l` / `;` | Focus left / down / up / right |
| `$mod+Left` / `Down` / `Up` / `Right` | Focus left / down / up / right |
| `$mod+Shift+j` / `k` / `l` / `;` | Move window left / down / up / right |
| `$mod+Shift+Left` / `Down` / `Up` / `Right` | Move window left / down / up / right |

### Resize mode (enter with `$mod+Shift+d`)

| Keybind | Action |
| --- | --- |
| `j` / `k` / `l` / `;` | Shrink width / grow height / shrink height / grow width |
| `Left` / `Down` / `Up` / `Right` | Same as above with arrows |
| `Return` / `Escape` / `$mod+r` | Exit resize mode |

### Workspaces

| Keybind | Action |
| --- | --- |
| `$mod+1`..`$mod+0` | Switch to workspace 1..10 |
| `$mod+Shift+1`..`$mod+Shift+0` | Move window to workspace 1..10 |

### Media / hardware keys

| Keybind | Action |
| --- | --- |
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±10% |
| `XF86AudioMute` | Toggle mute |
| `XF86AudioMicMute` | Toggle mic mute |
| `XF86AudioPlay` / `Next` / `Prev` / `Stop` | playerctl media controls |
| `XF86MonBrightnessUp` / `Down` | Brightness ±5% |

### Screenshots / recording

| Keybind | Action |
| --- | --- |
| `$mod+Shift+s` | Region screenshot to clipboard (grim + slurp) |
| `F9` | Toggle screen recording |

### Bar

| Keybind | Action |
| --- | --- |
| `$mod+b` | Toggle waybar visibility |
