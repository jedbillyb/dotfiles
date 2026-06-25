# dotfiles

My personal configuration files.

## Contents

- `sway/config` - Sway window manager config
- `i3/config` - i3 window manager config (legacy)
- `waybar/` - Waybar config, style, and status scripts (VPN + caffeine indicators)
- `wofi/config` - Wofi app launcher config (bound to mod+r)
- `xdg-desktop-portal/` - Portal backend selection so Flatpak apps get a working file picker on sway (`*-portals.conf`)
- `shell/` - Shell dotfiles (`.bashrc`, `.zshrc`, `.bash_profile`, `.profile`, `.inputrc`)
- `git/gitconfig` - Git config (no secrets: GPG signing uses a key ID, auth delegates to `gh`)
- `scripts/vpn-toggle.sh` - WireGuard VPN toggle (bound to mod+v)
- `scripts/caffeine-toggle.sh` - Stay-awake toggle: blocks idle lock + lid suspend (bound to mod+c)
- `scripts/sway-idle.sh` - swayidle launcher (idle lock / screen-off), restartable by the caffeine toggle
- `scripts/openclaw-send` - openclaw helper script
- `wireguard/wg0.conf.template` - WireGuard client config template (fill in private key)

## Install

```sh
git clone https://github.com/jedbillyb/dotfiles ~/projects/dotfiles
cd ~/projects/dotfiles
./install.sh
```

`install.sh` is idempotent - safe to re-run after pulling updates. It:

- symlinks `sway/config`, `i3/config`, `waybar/`, and `wofi/config` into `~/.config`
- symlinks the shell dotfiles and `gitconfig` into `~`
- symlinks the helper scripts into `~/.local/bin` and marks them executable
- copies the WireGuard template to `/etc/wireguard/wg0.conf` (via `sudo`) only
  if no config is already there

Any existing real file in the way is backed up to `<file>.bak` before the
symlink replaces it. Make sure `~/.local/bin` is on your `PATH`.

The steps below are **not** automated and still need doing once per machine.

### Flatpak file picker on sway

Flatpak apps (e.g. OrcaSlicer) open file dialogs via xdg-desktop-portal. The
wlroots backend only does screenshots/screencast, so install the GTK backend:

```sh
sudo xbps-install xdg-desktop-portal-gtk
```

The `xdg-desktop-portal/*-portals.conf` files (symlinked by `install.sh`) route
FileChooser to gtk and keep screenshots/screencast on wlr. `gtk.portal` ships
`UseIn=gnome`, so the explicit `FileChooser=gtk` line is required - the implicit
`default=gtk` is not enough on sway. Restart the portal frontend after first
install: `kill $(pgrep -f libexec/xdg-desktop-portal$)` (it re-activates on the
next request).

### VPN passwordless sudo

The VPN toggle needs `wg-quick up/down wg0` without a password. Drop a sudoers
rule **named so it sorts after `wheel`** (otherwise a broad `%wheel ALL` rule
overrides the NOPASSWD), pointing at the absolute `/usr/bin/wg-quick`:

```sh
echo 'jed ALL=(ALL) NOPASSWD: /usr/bin/wg-quick up wg0, /usr/bin/wg-quick down wg0' \
  | sudo tee /etc/sudoers.d/zz-wg-toggle
sudo chmod 0440 /etc/sudoers.d/zz-wg-toggle
sudo visudo -c
```

### Fingerprint / lock screen

`sway-idle.sh` runs swayidle and locks with **swaylock-fprintd**, a fork of
swaylock that accepts a fingerprint and a typed password concurrently (neither
blocks the other): <https://github.com/jedbillyb/swaylock-fprintd>. It expects
the fork's split PAM services (`/etc/pam.d/swaylock` password-only +
`/etc/pam.d/swaylock-fp` fprintd-only) and a non-setuid binary at
`~/.local/bin/swaylock-fprintd` — see that repo's README for the build and PAM
setup.

The idle stages are: lock at 5 min, screen off at 10 min. The screen-off
`timeout` carries a paired `resume 'swaymsg "output * dpms on"'` — without it
the display never wakes after an idle blank and you get a black screen that
needs a hard power-off. `after-resume` only covers system sleep, not the DPMS
idle-blank, so both are needed. The caffeine toggle (`mod+c`) stops/restarts
this script to inhibit idle locking.

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
| `$mod+v` | Toggle WireGuard VPN (status in bar, green when on) |
| `$mod+c` | Toggle caffeine / stay-awake (blocks idle lock + lid suspend; status in bar) |
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

### Screenshots

| Keybind | Action |
| --- | --- |
| `$mod+Shift+s` | Region screenshot to clipboard (grim + slurp) |

### Bar

| Keybind | Action |
| --- | --- |
| `$mod+b` | Toggle waybar visibility |
