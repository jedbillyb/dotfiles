# dotfiles

My personal configuration files.

## Contents

- `sway/config` - Sway window manager config
- `i3/config` - i3 window manager config (legacy)
- `waybar/` - Waybar config, style, and status scripts (VPN, caffeine, network,
  USB WiFi, AirDrop, AirPods, calendar, and Claude indicators). The calendar
  module styles two failure states, `auth` (Google OAuth token expired or
  revoked) and `stale` (fetching is failing and the cache has aged out), so a
  broken backend is visible instead of collapsing to an empty module
- `wofi/config`, `wofi/style.css` - Wofi app launcher config and theme
- `foot/foot.ini` - foot terminal config (sway runs `footclient` against a foot server)
- `xdg-desktop-portal/` - Portal backend selection so Flatpak apps get a working file picker on sway (`*-portals.conf`)
- `shell/` - Shell dotfiles (`.bashrc`, `.zshrc`, `.bash_profile`, `.profile`, `.inputrc`)
- `git/gitconfig` - Git config (no secrets: GPG signing uses a key ID, auth delegates to `gh`)
- `bin/spotlight` - Spotlight-style centered wofi launcher (bound to mod+r and mod+space)
- `scripts/vpn-toggle.sh` - WireGuard VPN toggle (bound to mod+Shift+v)
- `scripts/vpn-proxy.sh` - TCP-over-SSH fallback for networks that block UDP, so
  there is still a tunnel when WireGuard can't handshake (`up|down|status`)
- `scripts/show-desktop.sh` - Show-desktop toggle (bound to mod+d)
- `scripts/caffeine-toggle.sh` - Stay-awake toggle: blocks idle lock + lid suspend (bound to mod+Shift+c)
- `scripts/sway-idle.sh` - swayidle launcher (idle lock / screen-off), restartable by the caffeine toggle
- `scripts/sway-lock.sh` - Lock screen launcher (swaylock-fprintd, bound to mod+Shift+i)
- `scripts/touchpad-resume-fix.sh` - Unsticks the touchpad after resume (elogind hook + mod+Shift+r)
- `scripts/waybar-toggle.sh`, `scripts/waybar-run.sh` - Show/hide waybar (mod+b) and launch it
- `scripts/wifi-compare.sh` - Compares onboard vs USB WiFi adapter throughput
- `scripts/wifi-recover.sh` - Forces WiFi back to a known-good state after
  suspend or AWDL/AirDrop testing (bound alongside the touchpad fix on
  mod+Shift+r)
- `scripts/wifi-recover-root.sh` - Privileged half of that recovery, installed
  as a root-owned copy at `/usr/local/bin/wifi-recover-root`
- `scripts/touch-gestures.sh` - Touchscreen swipe gestures via `lisgd` (see
  "Touchscreen gestures" below)
- `udev/99-touchscreen-lisgd.rules` - Stable `/dev/input/touchscreen` symlink
  and group access for that daemon
- `scripts/openclaw-send` - openclaw helper script
- `scripts/zed-wrapper` - Launches Zed with `CLAUDE_LOCAL_API_KEY` set, so Zed
  accepts the local `claude-local` provider (see "Zed and the local Claude
  shim" below)
- `zed/dev.zed.Zed.desktop` - Patched Zed launcher entry (uses the wrapper, no
  duplicate launcher result)
- `wireguard/wg0.conf.template` - WireGuard client config template (fill in private key)

## Install

```sh
git clone https://github.com/jedbillyb/dotfiles ~/projects/dotfiles
cd ~/projects/dotfiles
./install.sh
```

`install.sh` is idempotent - safe to re-run after pulling updates. It:

- symlinks `sway/config`, `i3/config`, `waybar/`, `wofi/`, `foot/foot.ini`, and
  the `xdg-desktop-portal/*-portals.conf` files into `~/.config`
- symlinks the shell dotfiles and `gitconfig` into `~`
- symlinks the `scripts/` and `bin/` helpers into `~/.local/bin` and marks them
  executable
- symlinks `scripts/touchpad-resume-fix.sh` into
  `/usr/libexec/elogind/system-sleep/` (via `sudo`) so elogind runs it on resume
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

### AirPods battery module

`waybar/airpods-status.sh` is a symlink into the
[waybar-airpods](https://github.com/jedbillyb/waybar-airpods) repo, following the
same convention as the AirDrop module: the script lives with the project that
owns it, this repo only carries the link and the waybar wiring.

### LibreOffice Discord presence

The sway config autostarts
[libreoffice-discord-rpc](https://github.com/jedbillyb/libreoffice-discord-rpc),
which shows the LibreOffice document you're working on as Discord Rich Presence.
It subscribes to sway window events rather than polling, and holds the presence
for as long as any LibreOffice window is open.

It runs from that project's venv, so the binary must exist before the `exec` line
does anything:

```sh
cd /mnt/shared/projects/libreoffice-discord-rpc
python -m venv .venv && .venv/bin/pip install .
```

Plain `exec`, not `exec_always` — the daemon has no single-instance lock, so a
sway reload would leave a second copy fighting over the presence. Void has no
systemd, so there is no user unit for it here; the sway config *is* the autostart.

BlueZ exposes no battery interface for AirPods, so the numbers come from a
daemon in that repo which talks Apple's AACP protocol over L2CAP. Sway starts it
with `exec_always`; that is safe because the daemon takes an flock and a second
copy exits immediately. The module pushes updates to waybar with `SIGRTMIN+11`
rather than being polled, because AirPods only send battery on change.

It sits left of the AirDrop switch and doubles as a connect toggle: dimmed
`pods --` when disconnected, amber `pods ...` while connecting, then the battery
levels. Clicking connects or disconnects.

AirPods hold only one audio link at a time, and multipoint only works between
Apple devices on the same iCloud account, so a phone reclaims them constantly
and they never auto-connect back to this machine. When the phone has them,
BlueZ fails with `br-connection-unknown` and the link visibly flaps (a new
`(AVRCP)` input device appears in `dmesg` each attempt). There is no fix on this
end - disconnect them on the phone first, then click.

### Silencing blueman connect/disconnect popups

blueman-applet's `ConnectionNotifier` plugin fires a desktop notification every
time any Bluetooth device connects or disconnects. With AirPods that is constant
noise, and the bar already shows the state. Disable just that plugin (the
leading `!` is how blueman marks one disabled) and restart the applet:

```sh
gsettings set org.blueman.general plugin-list "['!ConnectionNotifier']"
pkill -f blueman-applet && (setsid blueman-applet >/dev/null 2>&1 &)
```

This lives in dconf rather than in this repo, so it does not survive a fresh
machine. Confirm it took with:

```sh
busctl --user call org.blueman.Applet /org/blueman/Applet \
  org.blueman.Applet QueryPlugins | grep -c ConnectionNotifier
```

which should print `0`. Note the setting **replaces** the plugin list, so add
any other `!Plugin` entries to the same array rather than running the command
again with a different one.

### WiFi recovery after AirDrop/AWDL testing

`$mod+Shift+r` reloads the sway config, re-probes a wedged touchpad, and runs
`wifi-recover.sh`, which is meant to always be able to get the network back
however AirDrop/AWDL testing left it. Restarting NetworkManager alone is not
enough: most of the damage is below it, in the driver and the kernel's netdevs,
and NetworkManager cannot associate through any of it. The three layers are:

1. `airdrop-helper wifi-reset` (from the airdrop-mt7921 repo) - monitor and
   P2P-GO vifs, mt76 `runtime-pm`/`deep-sleep`, rfkill, interface up.
2. `wifi-recover-root` (this repo) - everything that does not cover: an owl
   still running under its repo name, a stranded `awdl0`, the regulatory
   domain left where a run set it, the managed interface left in monitor type,
   mt76 power management when debugfs is unmounted (layer 1 mounts it in `up`
   but not in `wifi-reset`, so both knob writes fail silently), and
   NetworkManager or avahi-daemon still stopped because an `airdrop.sh` run
   was killed before its exit trap.
3. `nmcli` as the desktop user - radio on, networking on, interface managed,
   autoconnect back on, and a reconnect **only** if it is not already
   connected.

Every step is conditional, because this binding also fires on plain config
reloads with nothing wrong - it must never bounce a healthy association.

The root half runs as a root-owned copy at `/usr/local/bin/wifi-recover-root`
(a symlink into this repo would let anything able to write the repo run code as
root). `install.sh` copies it; the sudoers rule is manual, and like the VPN one
must be **named so it sorts after `wheel`**:

```sh
printf 'jed ALL=(root) NOPASSWD: /usr/local/bin/wifi-recover-root\n' \
  | sudo tee /etc/sudoers.d/zz-wifi-recover
sudo chmod 0440 /etc/sudoers.d/zz-wifi-recover
sudo visudo -c
```

Without the rule the keybinding still works - the privileged layers no-op
silently (there is no TTY to prompt on) and only the `nmcli` layer runs.

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
idle-blank, so both are needed. The caffeine toggle (`mod+Shift+c`) stops/restarts
this script to inhibit idle locking.

### Touchpad wedges after resume

The I2C-HID touchpad (`CRQ1080:00 0488:1051`, on `i2c-6` under the
`AMDI0010:03` platform controller) can come back broken after suspend.
`scripts/touchpad-resume-fix.sh` handles both failure modes, and runs from two
places: elogind calls it as a system-sleep hook (symlinked into
`/usr/libexec/elogind/system-sleep/`, recreated by `install.sh`), and
`$mod+Shift+r` runs it alongside the config reload as a manual escape hatch.
The touchscreen is on a separate controller and is never affected.

The two modes look different, and it's worth knowing which you have:

- **Cursor moves nowhere, but clicks still register.** The device re-enumerates
  but `hid-multitouch` leaves it in a degenerate mode: it streams bare
  coordinates (`ABS_X/Y`, `ABS_MT_POSITION_X/Y`) with no `BTN_TOUCH` and no
  `ABS_MT_TRACKING_ID`. libinput won't synthesise motion from a touchpad that
  never reports a finger down, so motion is dropped while the separate
  `BTN_LEFT` path keeps working. Fixed by rebinding at the `i2c_hid_acpi`
  level, which re-probes the HID device and re-sends the mode-switch feature
  report.
- **Cursor fully frozen or only twitching.** The AMD I2C controller itself is
  dead. The `i2c_hid_acpi` rebind fails with "No such device" and you have to
  reset one level up, at the `i2c_designware` platform driver.

To tell them apart, compare what the kernel emits against what libinput makes
of it — if the kernel shows coordinates but libinput shows nothing but
`DEVICE_ADDED`, it's the first mode:

```sh
sudo libinput debug-events --device /dev/input/eventN
```

Note that `dwt` (disable-while-typing) is on, so libinput legitimately drops
motion while you type. Test by swiping with the keyboard idle, or you'll
misread normal behaviour as the bug.

### Touchscreen gestures

The Wacom digitiser (`Wacom HID 5323 Finger`, `056a:5323`) drives iPad-style
swipes through [`lisgd`](https://git.sr.ht/~mil/lisgd), launched by
`scripts/touch-gestures.sh` from `exec_always` in the sway config.

sway's own `bindgesture` is not an option here: it fires on libinput *gesture*
events, which touchpads emit and touchscreens do not. lisgd reads the raw touch
events off the evdev node and synthesises swipes itself, which is the whole
reason it exists.

| Gesture | Action |
| --- | --- |
| 1 finger, in from the **right** edge | Next workspace |
| 1 finger, in from the **left** edge | Previous workspace |
| 1 finger, up from the **bottom** edge | Spotlight launcher |
| 4 fingers, left / right (anywhere) | Grow / shrink focused window width |
| 4 fingers, down / up (anywhere) | Grow / shrink focused window height |
| 3 fingers, left / right (anywhere) | Focus window left / right |
| 3 fingers, up (anywhere) | Toggle fullscreen |
| 3 fingers, down (anywhere) | Close window |

The single-finger gestures are anchored to a screen edge on purpose. lisgd
cannot swallow the touches it watches, so the app underneath sees them too — a
mid-screen swipe would scroll the page as well as switch workspace. The edge
strips are 50px of mostly dead space, which keeps the two apart.

The same problem is why resize sits on **four** fingers rather than two. Two is
already spoken for by applications: horizontal is back/forward in browsers,
vertical is scroll, so a 2-finger resize fires the app's gesture as well as
sway's. Nothing binds four, and the digitiser tracks 10 simultaneous contacts
(`ABS_MT_SLOT` max 9), so there is room to spare.

Build and install it with:

```sh
git clone https://git.sr.ht/~mil/lisgd /mnt/shared/projects/lisgd
cd /mnt/shared/projects/lisgd && make WITHOUT_X11=1
install -m755 lisgd ~/.local/bin/lisgd
```

`WITHOUT_X11=1` matters. lisgd checks `WAYLAND_DISPLAY` first and falls back to
`DISPLAY` for screen geometry, and an X11-enabled build that can't open the
display just dies.

Two traps worth knowing about, both already handled by the script:

- **sway hands its children `PATH=/usr/bin:/usr/sbin`**, so nothing in
  `~/.local/bin` is on the path for an `exec_always` line. The script calls
  lisgd by absolute path.
- **`usermod -aG input` only takes effect at the next login.** The script
  re-execs itself under `sg input` when it finds it lacks the group, so
  gestures work immediately on the session where it was first set up.

To debug, kill the daemon and run it by hand with `-v` to see what each swipe
is being recognised as:

```sh
pkill lisgd
~/.local/bin/lisgd -v -d /dev/input/touchscreen -g '1,RL,R,*,R,notify-send swiped'
```

### Touch-resizing windows and invisible borders

Dragging a window edge to resize it needs a border to grab — with `border none`
there is no hit region at all, and tiled windows can only be resized from the
keyboard. But a visible 5px frame around everything is ugly, and taking 5px out
of each window's content is worse.

Both are avoidable. sway alpha-blends border colours over the wallpaper layer,
so `#00000000` gives a border that is fully invisible and still grabbable. The
space it costs is handed straight back by moving the 10px separation out of the
gaps and into the borders:

```
default_border pixel 5      # was: none
gaps inner 0                # was: 10
gaps outer 5                # was: 0
client.* ... #00000000 ...  # transparent border, background, indicator
```

Two adjacent windows now sit flush, with 5px of transparent border each making
up the same 10px gutter as before, and the outer gap of 5 plus a 5px border
reproduces the old 10px screen-edge inset. Window *content* rects come out
byte-identical to the old borderless layout — the borders are free.

The border width is pinned by wanting every gap the same. A window's rect
cannot extend past the output and outer gaps clamp there, so the screen-edge
inset always equals the border width, while the gutter between two windows is
*two* borders. Equal gaps therefore forces `outer == border` and
`gutter == 2 * border`, and a 10px look caps the border at 5. Widening the grab
strip means widening every gap with it (`border 10` + `outer 10` gives 20px
throughout). Negative outer gaps don't buy a way out — sway clamps them at the
output edge.

Which leaves a real limitation: 10px is about a fifth of a fingertip on this
screen (~5.6 px/mm), so dragging a border by touch is fiddly. The 4-finger
resize gestures above are the way round it — they need no aiming.

`resize` wants a space before the unit: `resize grow width 60 px`. The
unspaced `60px` is not a parse error, it just quietly resizes by the wrong
amount.

`default_border` only applies to windows created after it, so after a reload
existing windows keep their old setting until you re-run
`swaymsg '[app_id=".*"] border pixel 5'` or restart them.

### Zed and the local Claude shim

Zed's commit-message button is pointed at `zed-claude-shim`
(`/mnt/shared/projects/zed-claude-shim`), a localhost OpenAI-compatible server
that forwards to the `claude` CLI. Zed will not use a custom
`openai_compatible` provider until it has an API key for it, and it normally
keeps that key in the Secret Service keyring.

Two things get in the way on this machine:

1. **No keyring daemon runs**, so Zed cannot store or read a key at all. The
   log shows `org.freedesktop.secrets was not provided by any .service files`
   and `Failed to authenticate provider: ...` for every key-based provider.
2. **emptty does not source `~/.profile`.** The sway session environment is
   bare (`PATH=/usr/bin:/usr/sbin`), so exports in `shell/profile` never reach
   GUI apps. Worth knowing beyond Zed: `GDK_BACKEND` and `SAL_USE_VCLPLUGIN`
   set there are currently not applied to anything.

Zed's fallback for a missing keyring is an environment variable derived from
the provider name, so provider `claude-local` reads `CLAUDE_LOCAL_API_KEY`.
`scripts/zed-wrapper` sets it and execs the real binary. The value is not a
secret: the shim listens on loopback and runs with `SHIM_API_KEY` unset, so it
never checks the token; Zed only requires the variable to be present.

`install.sh` symlinks the wrapper into `~/.local/bin` like any other script.
Pointing Zed's launcher at it is a manual step, because the desktop entry
belongs to Zed rather than this repo. The patched copy is kept here:

```sh
cp zed/dev.zed.Zed.desktop ~/.local/share/applications/dev.zed.Zed.desktop
```

**A Zed update overwrites that file**, reverting `Exec` to the raw binary. If
the commit button starts saying "configure an LLM provider" again after an
upgrade, re-run the copy above. Zed's own template lives at
`~/.local/zed.app/share/applications/dev.zed.Zed.desktop` with a bare
`Exec=zed`, which the installer rewrites to an absolute path, so patching the
template is not reliable, hence the copy.

Two other fixes are baked into that entry:

- **`Actions=NewWorkspace` is removed.** wofi's drun mode lists desktop actions
  as their own result, so Zed showed up twice in the launcher.
- **`Categories` is trimmed** from `Utility;TextEditor;Development;IDE` to drop
  `Utility`. `Utility` and `Development` are both main categories, which lists
  the app twice in categorised menus.

## Sway keybindings

`$mod` = **Super** (Mod4, the Windows key).

### Applications

| Keybind | Action |
| --- | --- |
| `$mod+Return` | Terminal (footclient) |
| `$mod+r` | App launcher (`spotlight` - wofi centered on the focused output) |
| `$mod+space` | App launcher (same as `$mod+r`) |
| `$mod+f` | Firefox |
| `$mod+c` | Google Chrome |
| `$mod+p` | File manager (Thunar) |
| `$mod+n` | noted quick-add bar (from the separate `noted` project); `$mod+n` again or `Escape` dismisses it |

### System / session

| Keybind | Action |
| --- | --- |
| `$mod+Shift+v` | Toggle WireGuard VPN (status in bar, green when on) |
| `$mod+Shift+c` | Toggle caffeine / stay-awake (blocks idle lock + lid suspend; status in bar) |
| `$mod+Shift+i` | Lock screen (swaylock-fprintd, auto fingerprint) |
| `$mod+Shift+o` | Exit sway, back to TTY |
| `$mod+Shift+p` | Power off |
| `$mod+Shift+r` | Reload sway config (also re-probes a wedged touchpad and recovers WiFi) |

### Window management

| Keybind | Action |
| --- | --- |
| `$mod+q` | Close window |
| `$mod+d` | Show desktop (hide everything); press again to come back |
| `$mod+h` | Split horizontal |
| `$mod+s` | Stacking layout |
| `$mod+w` | Tabbed layout |
| `$mod+e` | Toggle split layout |
| `$mod+Shift+f` | Toggle fullscreen |
| `$mod+Shift+space` | Toggle floating |
| `$mod+grave` | Toggle focus between tiling and floating |
| `$mod+a` | Focus parent |
| `$mod+Shift+d` | Enter resize mode |

`show-desktop.sh` works by switching to an empty workspace named `D` and
switching straight back, tracking the previous workspace per output. It
deliberately does **not** stash windows in the scratchpad: the scratchpad forces
a window floating and resizes it (a visible size-pop when it returns), and
lifting containers out of the tree loses the split layout, so they never land
back in the same spots. Switching workspaces leaves the tree untouched, so the
restore is exact and instant. The workspace is a single character because
waybar 0.15's `sway/workspaces` has no ignore-list - a longer name would sit in
the bar and shove the centred clock off.

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

Workspace `D` is the show-desktop scratch workspace (see above). It only exists
while `$mod+d` is toggled on - sway drops it again as soon as it is empty and
unfocused.

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
| `` grave `` | Full screenshot saved to `/mnt/shared/pictures/Screenshots/` |
| `` Shift+grave `` | Same, with the cursor included |

The two `grave` binds are deliberately **not** prefixed with `$mod` - a bare
backtick takes the screenshot. They use `--to-code` so they follow the physical
key rather than the keymap symbol.

### Bar

| Keybind | Action |
| --- | --- |
| `$mod+b` | Toggle waybar visibility |

## Touchscreen gestures

| Gesture | Action |
| --- | --- |
| 1 finger, in from right edge | Next workspace |
| 1 finger, in from left edge | Previous workspace |
| 1 finger, up from bottom edge | Spotlight launcher |
| 4 fingers left / right | Grow / shrink focused window width |
| 4 fingers down / up | Grow / shrink focused window height |
| 3 fingers left / right | Focus window left / right |
| 3 fingers up | Toggle fullscreen |
| 3 fingers down | Close window |

Windows also resize by dragging their (invisible) edges. See "Touchscreen
gestures" and "Touch-resizing windows and invisible borders" above.
