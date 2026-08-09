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
- `bin/spotlight` - Spotlight-style centered wofi launcher (bound to mod+r and
  mod+space); tap or click outside the box to dismiss it
- `scripts/wofi-dismiss.py` - Closes it on a tap outside the box, by watching
  the touchscreen (see "Touchscreen gestures" below)
- `scripts/wofi-backdrop.py` - Closes it on a *click* outside the box, via a
  transparent full-screen layer-shell surface underneath it
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
- `scripts/touch-shield.py` - Transparent strips along the gesture edges so a
  swipe does not also land on the app underneath. **Unfinished and disabled in
  the sway config** — see "Stopping the swipe from also hitting the app"
- `scripts/touch-resize.sh` - What a resize gesture runs: writes one line to a
  FIFO and exits, so the gesture pays ~1ms. Its exit status tells lisgd whether
  the gesture was really a resize
- `scripts/touch-resized.py` - The daemon behind it, holding the sway IPC socket
  open; resizes the tiled window boundary nearest the gesture, giving the 10px
  gap a fingertip-sized grab region
- `scripts/workspace-new.py` - Switches to the nearest *unused* workspace number
  in one direction, which a long edge swipe runs; `workspace next_on_output`
  only cycles ones that already exist
- `patches/lisgd-export-gesture-coords.patch` - Local lisgd patch exporting
  `LISGD_X`/`LISGD_Y` (anchor) and `LISGD_CUR_X`/`LISGD_CUR_Y` (live position),
  which touch resize depends on
- `patches/lisgd-cardinals-before-diagonals.patch` - Matches the four cardinal
  directions before the diagonals, so a wide `-r` stops the diagonals swallowing
  most real swipes
- `patches/lisgd-pressed-decline.patch` - Lets a pressed gesture's command exit
  non-zero to say it did nothing, so a no-op resize stops destroying the swipe
  it was part of
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
| 1 finger, in from the **right/left** edge, **two thirds across** | New *empty* workspace that way |
| 1 finger, up from the **bottom** edge | Spotlight launcher |
| 1 finger, down from the **top** edge, a third of the screen or more | Close the focused window |
| 1 finger, near a window boundary (not on an edge) | Drag that boundary (see below) |

`workspace next_on_output` only cycles the workspaces that already exist, so
there is otherwise no way to swipe to somewhere blank and start something in it —
which matters much more without a keyboard than with one. Carrying the same edge
swipe two thirds of the way across the screen (`L`, ~1270px) runs
`scripts/workspace-new.py` instead, which switches to the nearest *unused*
number in that direction. Numbers here are sparse, so going right from 1 lands
on 3 rather than one past the end, keeping the new workspace next to where you
were. It does nothing if you are already on an empty workspace, so repeating the
swipe cannot leave a trail of empties.

Those two bindings are listed **before** the plain ones. lisgd takes the first
match and a distance of `*` matches everything, so an `L` binding placed after
one would never be reached. Distance is a floor, not a band — the test is
`configured <= measured`.

Close-window carries a distance guard (`M` — at least a *medium* swipe, 400px
here) that nothing else does, because it is the only destructive gesture, and it
is anchored to the top edge rather than bound to two fingers anywhere. That is
not cosmetic: it is the only shape of release gesture that survives here, for
the reason described under "a pressed gesture can decline" below. The old
`2,DU,*,M,R` never fired once — a verbose capture caught all four attempts
arriving as *swipe -1*, ground down by no-op resize fires.

Nothing is bound to three or four fingers. A release gesture only counts the
fingers whose *own* swipe matched, and with three or four down one of them
almost always drifts off direction, so the count falls short and nothing
happens.

Dropping them is what makes the loose recognition below safe — switching
workspace, opening the launcher and resizing are all reversible, so a stray
match costs a swipe back.

`-t 25` is how far a swipe must travel to count at all (~4.5mm here). Distance was
never what made a swipe fail to register, though — three other defaults were,
and all three are loosened:

| flag | default | here | why |
| --- | --- | --- | --- |
| `-r` | 15 | 45 | Degrees of slack on direction. A swipe had to be within 15° of dead horizontal, and a thumb coming in from the edge arcs. |
| `-m` | 800 | 5000 | How long the gesture may take. A slow, deliberate swipe never fired. Also gates the pressed path, so at 1000 a pause of more than a second mid-drag killed resizing until you lifted. Raised again for the new-workspace swipe, which is an arm movement rather than a flick. |
| `-s` | 1.0 | 2.0 | Scales the 50px edge strips to 100px. Workspace swipes only count if they start or end in one. |

**Raising `-r` on its own made swipes worse, and this is worth knowing before
touching it again.** lisgd tests the eight directions in ascending angle order
and takes the first whose band — the direction ±`-r` — contains the swipe. Past
22.5° those bands overlap, and since the diagonals are interleaved with the
cardinals, a diagonal claims part of the range belonging to the cardinal after
it. At `-r 40`, `URDL` (225°) covered everything up to 265°, leaving a
right-to-left swipe accepting only 265–310°: 40° of slack one way and 5° the
other. Real swipes arc, so they mostly landed in the stolen range and came out
as a diagonal nothing was bound to. A verbose capture showed **ten of twelve**
edge swipes lost this way — the "only works one in three" symptom.

`patches/lisgd-cardinals-before-diagonals.patch` asks the four cardinals first
and leaves the diagonals the gaps. With that applied, `-r 45` makes the cardinals
tile the whole circle: every swipe resolves to exactly one of them and none is
silently discarded. Nothing diagonal is bound, so they lose nothing.

The single-finger *workspace* gestures are anchored to a screen edge on purpose.
lisgd cannot swallow the touches it watches, so the app underneath sees them
too — a mid-screen swipe would scroll the page as well as switch workspace. The
edge strips are 100px of mostly dead space (50px scaled by `-s 2.0`), which
keeps the two apart.

A single-finger swipe resizes the *boundary the gesture started near*, via
`scripts/touch-resize.sh`. It is bound in lisgd's **pressed** mode (`P` rather
than `R`), so it fires every 10px *during* the drag instead of once on
release — the window tracks your finger rather than hopping when you let go.
That script does its own hit test with 60px of slop, which is the whole point:
it gives the gap between two windows a fingertip-sized grab region while the gap
itself stays 10px on screen. Sway cannot do this — `find_edge()` tests against
`border_thickness`, so its own grab region is exactly the visible border. Away
from any boundary the script is a no-op, so a stray swipe mid-window changes
nothing.

That no-op is also what makes binding a **single** finger safe, since one finger
dragging is how you scroll everything. It has to be cheap as well as silent,
though: a miss leaves a negative cache entry (`con 0`, on a 1s TTL rather than
the 3s a live drag gets), so the fires that follow it cost ~5ms instead of
re-running the 60ms tree search over and over while you scroll.

The single-finger resize is bound to edge `N` — *not* near any edge — rather
than `*`. When a pressed gesture matches, lisgd advances that slot's leg start
to the current point, so the release gesture afterwards sees only the leftover
stub and no longer registers as a swipe; with `*` the edge swipes above would
simply never fire. `N` keeps them apart for the whole drag, because that leg
start only advances on a match — a swipe begun at the edge keeps measuring from
the edge and never looks like edge `N`. The cost is that a one-finger resize
stops when the drag reaches the edge strip.

`N` is only half the answer, though: it protects gestures that *start* on an
edge, and nothing else. See "a pressed gesture can decline" below for the rest.

#### A pressed gesture can decline

Binding a conditional action to pressed mode has a trap in it, and it cost every
mid-screen release gesture in this config until it was found. lisgd advances the
slot's leg start on each pressed match, and it counts a **binding match** as
success regardless of what the command did. The resize bindings usually do
nothing — there is rarely a boundary within 60px, since dragging a finger is
mostly just scrolling — yet each no-op still consumed the swipe. Anything that
began away from a screen edge therefore arrived at touch-up measuring about 10px
and read as *no swipe at all*, which is why close-window could never fire.

`patches/lisgd-pressed-decline.patch` makes a non-zero exit mean "matched but
declined": the leg is left alone to grow into whatever gesture it turns out to
be. `touch-resized.py` keeps a flag file present exactly while it holds a
boundary and `touch-resize.sh` tests for it, so the decision stays where the
knowledge is and costs one syscall on the gesture's critical path. Declining
still advances a separate throttle (`xfire[]`), or a binding that never acts
would fire on every motion event of every scroll.

This is why close-window is anchored to an **edge** rather than bound to two
fingers mid-screen: an edge-anchored swipe was immune even before the patch,
since the edge is computed from the touch-down point and stays `L`/`R`/`T`/`B`
for the whole drag, so an `N`-gated resize can never match it.

#### Keeping the patches applied

Three local patches are needed, in this order. Reapply after any lisgd update, or
touch resize silently stops working and gestures start eating each other:

```sh
cd /mnt/shared/projects/lisgd
for p in lisgd-export-gesture-coords \
         lisgd-cardinals-before-diagonals \
         lisgd-pressed-decline; do
  git apply /mnt/shared/projects/dotfiles/patches/$p.patch
done
make WITHOUT_X11=1 && install -m755 lisgd ~/.local/bin/lisgd
```

The first exists because upstream lisgd does not tell the command *where* the
gesture started — it calls `system()` and nothing else. It adds `LISGD_X` /
`LISGD_Y` (and `LISGD_CUR_X` / `LISGD_CUR_Y`) to the environment first,
capturing them before `resetslot()` wipes them.

**The boundary is moved *to* the finger, not *by* a step**, and that is the
whole reason it keeps up. Stepping (`resize grow width N px` per fire) makes
the work proportional to how far you drag: lisgd blocks on each call, so a fast
drag queues fires faster than they can run and the boundary arrives late,
still catching up after your fingers have stopped. Shrinking the step makes it
*worse*, because it multiplies the number of calls. Positioning absolutely
(`resize set width <finger - origin> px`) is idempotent, so a backlog collapses
to the newest fire and drag speed stops mattering.

That needs the live touch position, so the lisgd patch exports `LISGD_CUR_X` /
`LISGD_CUR_Y` alongside the anchor, and the daemon remembers the window's size
at the moment it was grabbed. Each fire sets it to that size plus how far the
*firing finger* has travelled from *its own* anchor.

Both halves of that matter, because **lisgd tracks each finger in a separate
slot** and reports whichever one fired — so a two-finger drag reports two
anchors and two live positions, a hand's width apart:

- Driving the size off an absolute finger position makes the boundary flip
  between the two fingers, oscillating by the width of your grip. Using each
  finger's delta from its own anchor gives the same answer for both.
- Remembering the grabbed boundary as tightly as it is picked (60px) makes every
  other fire miss, re-run the tree search, and record the *other* finger's
  anchor — the fingers thrash it between them, which reads as lag punctuated by
  snaps. So the anchor match is 250px for two fingers, far wider than the 60px
  `SLOP` used to pick the boundary in the first place, and 60px for one.

That memory's TTL measures the gap *between* fires, not the age of the drag —
every fire refreshes it. Getting that wrong is invisible until you drag: it went
stale a fixed time after the *first* fire, so a drag died after 3-5 steps, and
died permanently, because a re-pick searches near the original anchor and by
then the boundary has been dragged well clear of it.

**Per-fire cost is the lag**, because lisgd blocks in `system()` until the
command returns, and in pressed mode that is every 10px of finger travel. So the
work is not done there at all. `scripts/touch-resized.py` is a daemon holding
the sway IPC socket open with the drag state in memory, and `touch-resize.sh` —
the thing lisgd actually runs — is one `sh` that writes a line to a FIFO and
exits, about 1.2ms. Everything else happens off the gesture's critical path.

Getting there took three goes, and the numbers are why:

| | per fire | first fire of a drag |
| --- | --- | --- |
| all in Python | 49ms | 49ms |
| sh + cache file, Python picker | ~5ms | ~60ms |
| FIFO to a resident daemon | ~1.2ms | ~1.2ms |

Nearly all of the Python was the interpreter starting up (21ms for
`python3 -c pass`), so caching *inside* it saved nothing. Even the sh version
paid ~3ms just to start bash and another ~2ms to fork `swaymsg`. Once the answer
is "stop starting programs", the FIFO write is all that is left.

With that gone, the limit is **`-T`, how far the finger travels between fires**,
which is why it dropped 20 → 10px (~1.8mm here) once fires got cheap. Below that
there is nothing to win: at ordinary drag speeds 10px already fires faster than
the display refreshes, so the extra updates are thrown away while still making
clients relayout. Note this is not a reversal of "smaller steps made it worse" —
that was true while each fire *stepped* the boundary, so the work grew with the
drag. Fires are idempotent now, so more of them is just a finer sample.

Two details make that FIFO safe. The writer opens it **read-write**, not
write-only: a write-only open blocks until a reader appears, so a dead daemon
would hang lisgd on every gesture, permanently. Read-write never blocks, so with
no daemon the line just goes nowhere. And `touch-gestures.sh` supervises the
daemon in a background loop rather than merely starting it, since its death is
otherwise silent — the writes keep succeeding into a pipe nobody reads.

The daemon also drains the FIFO and acts only on the newest line. Each fire
positions the boundary absolutely, so replaying a backlog would just walk stale
finger positions to the same destination.

### Dismissing the launcher by tapping or clicking away

`bin/spotlight` runs two helpers alongside wofi so the launcher closes when you
tap or click off it, instead of having to reach for Escape. wofi has no option
for this, and the two input paths need different answers.

**Touch** is handled by `scripts/wofi-dismiss.py`, which reads touch-downs off
`/dev/input/touchscreen` (same `input` group as the gesture daemon) and compares
them against the rectangle spotlight computes to place the box. Coordinates come
off the digitiser in its own units (13788 x 8616 here, not 1920 x 1200), so they
are scaled by the axis ranges read with `EVIOCGABS`. The decision is made at the
end of each event packet rather than on the `BTN_TOUCH` event, because a new
contact's X and Y can be reported either side of it.

**Clicks** cannot work that way, and neither of the obvious alternatives holds
up:

- *sway focus events.* A click focuses the window under it, but sway only emits
  an event when the focused container actually changes. wofi holds keyboard
  focus as a layer surface without changing that container, so clicking the
  window you were already using — the likeliest target — emits nothing. Apps
  also churn focus on their own; Firefox does it about once a second while
  playing video, which dismissed the launcher on its own in testing.
- *reading evdev.* A mouse or touchpad reports relative motion, so the kernel
  events never say where the pointer is, and sway's IPC has no cursor position
  to ask for (`get_seats` carries devices and focus, no coordinates).

So `scripts/wofi-backdrop.py` stops trying to work out where the click went and
puts something there to catch it: a full-screen, fully transparent layer-shell
surface (gtk-layer-shell) that exits when clicked. spotlight waits on whichever
of the two ends first — hence `#!/bin/bash`, for `wait -n`.

Three things that surface has to get right, each of which broke something:

- **Layer.** The backdrop is on `top`, and `wofi/config` sets `layer=overlay` to
  put the launcher above it. Stacking within a layer follows the order surfaces
  are created, which is a race between two processes starting — and the backdrop
  lost it, swallowing wofi's own clicks. A layer apart is unambiguous.
- **Exclusive zone** must be `-1`. The default reserves screen space, shoving
  every tiled window aside for as long as the launcher is open.
- **Keyboard mode** must be `NONE`, or the backdrop takes focus and you cannot
  type in the launcher.

`Gdk` also needs pinning to 3.0 alongside `Gtk`: left alone, gi loads the newest
typelib (4.0) and GtkLayerShell then fails against it.

Clicking an entry still launches it — verified against a control run with no
backdrop, which also showed that a *single* click never launches in wofi 1.5.3.
It selects; activation is a double-click or Enter.

### Stopping the swipe from also hitting the app (unfinished)

**Status: written, disabled in `sway/config`.** Catching a swipe works; handing a
tap back works exactly once. Uncomment the `exec_always` line once the bug below
is fixed.

lisgd reads the touchscreen passively off its evdev node — that is what lets it
see gestures at all, but the compositor still delivers those same touches to
whatever is underneath, so an edge swipe also scrolls or drags the app it started
on. Reading evdev cannot prevent that, and an exclusive grab would take touch
from every app.

The only thing that stops the app seeing a touch is another surface taking it
first. `scripts/touch-shield.py` puts a layer-shell strip along each gesture edge
to do exactly that. Touch focus stays with the surface that got the touch-down,
so shielding the *start* of a swipe shields all of it.

That alone makes the strips dead zones, which is why a first version kept them
only as wide as the window gap (10px) — a Wayland surface that accepts touch
accepts the pointer too, measured, not assumed: with a 100px strip a click at
x=30 landed on the strip rather than the window, and at the right-hand edge that
is where scrollbars live.

The current version is the wide one that hands back what it should not have
taken: a touch that turns out to be a tap rather than a swipe is replayed to the
app as a click — clear the input regions, drive sway's cursor to the spot, click,
restore the regions. Verified working for the first tap.

**The open bug:** the strips go permanently input-transparent after that first
give-back, so the shield is inert from then on. Restoring the input region by
handing back a full-size rectangle is what fails; `None` (meaning "no input shape
at all") is the documented way and is what the code now does, but that change is
untested — the last run still showed 1 give-back out of 3 clicks. Failure
direction is safe: an unrestored region means the strips stop taking input, not
that they swallow it.

What the approach cannot give back either way is a *drag* that starts in a strip
and is not a swipe — scrolling a page from within the last 100px. Replaying a
press is one command; replaying a live drag would mean tracking it the whole way.

`TOUCH_SHIELD_WIDTH` sets the thickness, `TOUCH_SHIELD_DEBUG=1` tints the strips
and logs each give-back — placing an invisible surface is otherwise guesswork.

**Two fingers cannot be made exclusive.** lisgd can't swallow the touch, so a
browser sitting under that 60px strip still reads a horizontal 2-finger swipe
as back/forward and will navigate while the window resizes. Only about 10px of
the strip (the gap itself) is free of any app surface. The 4-finger bindings
exist for that reason: nothing binds four, and the digitiser tracks 10
simultaneous contacts (`ABS_MT_SLOT` max 9), so they resize the focused window
from anywhere with no aiming and no app conflict.

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
| 1 finger, in from right/left edge, two thirds across | New empty workspace that way |
| 1 finger, up from bottom edge | Spotlight launcher |
| 1 finger, down from top edge, a third of the screen | Close the focused window |
| 1 finger near a window boundary (not on an edge) | Drag that boundary |

Windows also resize by dragging their (invisible) edges. See "Touchscreen
gestures" and "Touch-resizing windows and invisible borders" above.
