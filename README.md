# dotfiles

My personal configuration files.

## Contents

- `sway/config` - Sway window manager config. Forces backlight to 100% on every
  start/reload (`amdgpu_bl0` doesn't reset to max on boot) via `brightnessctl`,
  which needs its own udev rule (`90-brightnessctl.rules`, ships with the
  package) granting the `video` group write access to
  `/sys/class/backlight/*/brightness` — udev only applies that on an `add`
  event, so a device already attached at rule-install time needs
  `udevadm trigger --subsystem-match=backlight --action=add` once to pick it up
- `i3/config` - i3 window manager config (legacy)
- `waybar/` - Waybar config, style, and status scripts (VPN, caffeine, network,
  WiFi band, Bluetooth, AirDrop, AirPods, calendar, heat pump, and Claude indicators). The calendar
  module styles two failure states, `auth` (Google OAuth token expired or
  revoked) and `stale` (fetching is failing and the cache has aged out), so a
  broken backend is visible instead of collapsing to an empty module. Clicking
  the module forces an immediate re-fetch; clicking it while it shows `cal auth`
  opens the Google OAuth consent flow in a terminal, so the 7-day token expiry is
  fixed from the bar instead of by hand
- `wofi/config`, `wofi/style.css` - Wofi app launcher config and theme
- `foot/foot.ini` - foot terminal config (sway runs `footclient` against a foot server)
- `xdg-desktop-portal/` - Portal backend selection so Flatpak apps get a working file picker on sway (`*-portals.conf`)
- `xdg-desktop-portal-wlr/config` - Which output the wlroots portal screencasts.
  `chooser_type` otherwise defaults to a chooser and slurp is installed, so every
  screen share - Miracast, a browser share, OBS - would open a drag-to-select
  region prompt first. `output_name` is per-machine; `swaymsg -t get_outputs`
  lists the valid names
- `airdrop/config` - Per-machine settings for
  [airdrop-mt7921](https://github.com/jedbillyb/airdrop-mt7921), sourced by both
  `airdrop.sh` and `airdropd`. Sets `RECV_DIR=/mnt/shared/airdrop` so received
  files land on the shared mount. It lives here rather than in that repo because
  the things that would otherwise carry the path - the waybar module, a sway
  keybind - are tracked files in a public checkout. Assignments use `${VAR:-…}`
  so the environment still overrides them.
- `wireplumber/wireplumber.conf.d/` - PipeWire session-manager drop-ins. Strips
  the sink-side Bluetooth roles so a phone can't push its audio into the
  laptop (see "Stopping the iPhone routing its audio here" below); headset
  roles are untouched
- `shell/` - Shell dotfiles (`.bashrc`, `.zshrc`, `.bash_profile`, `.profile`, `.inputrc`)
- `git/gitconfig` - Git config (no secrets: GPG signing uses a key ID, auth delegates to `gh`)
- `bin/spotlight` - Spotlight-style centered wofi launcher (bound to mod+r and
  mod+space); tap or click outside the box to dismiss it
- `scripts/wofi-dismiss.py` - Closes it on a tap outside the box, by watching
  the touchscreen (see "Touchscreen gestures" below)
- `scripts/wofi-backdrop.py` - Closes it on a *click* outside the box, via a
  transparent full-screen layer-shell surface underneath it
- `scripts/vpn-toggle.sh` - WireGuard VPN toggle (bound to mod+Shift+v)
- `scripts/vpn-amnezia.sh` - Full-tunnel AmneziaWG over UDP/123, for networks
  that fingerprint the WireGuard handshake (`up|down|status|diag`)
- `scripts/awg-client` - Server-side client provisioning and per-client egress
  addressing, deployed to the OCI box as `/usr/local/bin/awg-client`
- `scripts/awg-split-update` - Regenerates the Microsoft 365 split-tunnel range
  list `awg-client` bakes into new configs, deployed alongside it as
  `/usr/local/bin/awg-split-update`
- `scripts/vpn-split-watch` - Live view of which traffic is taking the VPN and
  which is going out direct
  (`add <name> [--ip A.B.C.D] [--json|--file] | list [--json] | del <name>`).
  Also the privileged half of [`awg-dashboard`](../awg-dashboard). Kept here
  as the source of truth; see "Rolling out AmneziaWG clients" below
- `waybar/vpn-status.sh` - Bar module showing *which* of the four transports is
  carrying the tunnel, since they differ by ~3x in speed
- `scripts/vpn-wstunnel.sh` - Full-tunnel WireGuard carried over TCP/443 via
  wstunnel, for networks that filter UDP (`up|down|status|diag`)
- `scripts/vpn-proxy.sh` - TCP-over-SSH fallback for networks that block UDP, so
  there is still a tunnel when WireGuard can't handshake (`up|down|status`)
- `scripts/show-desktop.sh` - Show-desktop toggle (bound to mod+d)
- `scripts/caffeine-toggle.sh` - Stay-awake toggle: blocks idle lock + lid suspend (bound to mod+Shift+c)
- `scripts/sway-idle.sh` - swayidle launcher (idle lock / screen-off), restartable by the caffeine toggle
- `scripts/sway-lock.sh` - Lock screen launcher (swaylock-fprintd, bound to mod+Shift+i)
- `scripts/touchpad-resume-fix.sh` - Unsticks the touchpad after resume (elogind hook + mod+Shift+r)
- `scripts/waybar-toggle.sh`, `scripts/waybar-run.sh` - Show/hide waybar (mod+b) and launch it
- `waybar/wifi-band.sh` - Bar module showing which band WiFi is actually on, and
  whether it is pinned there; click cycles auto / 5 GHz / 2.4 GHz. See "2.4 GHz,
  Bluetooth and the mt7921 combo chip" below for why the band is the thing worth
  watching on this machine
- `waybar/bluetooth-status.sh` - Bar module showing Bluetooth power state and
  connected device count, click toggles the controller
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
- `scripts/workspace-step.py` - Steps one workspace along by *number*, creating
  it if needed, which the two-finger edge swipe runs; `workspace next_on_output`
  only walks the ones that already exist
- `patches/lisgd-export-gesture-coords.patch` - Local lisgd patch exporting
  `LISGD_X`/`LISGD_Y` (anchor) and `LISGD_CUR_X`/`LISGD_CUR_Y` (live position),
  which touch resize depends on
- `patches/lisgd-cardinals-before-diagonals.patch` - Matches the four cardinal
  directions before the diagonals, so a wide `-r` stops the diagonals swallowing
  most real swipes
- `patches/lisgd-pressed-decline.patch` - Lets a pressed gesture's command exit
  non-zero to say it did nothing, so a no-op resize stops destroying the swipe
  it was part of
- `patches/lisgd-distance-px.patch` - Lets a gesture's distance field take an
  exact pixel count, since the built-in S/M/L buckets are thirds of the screen
  and leave nothing usable between "no guard" and "396px"
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
  the `xdg-desktop-portal/*-portals.conf` and `airdrop/config` files into
  `~/.config`
- symlinks the shell dotfiles and `gitconfig` into `~`
- symlinks the `scripts/` and `bin/` helpers into `~/.local/bin` and marks them
  executable (an explicit list, not a glob — a new script has to be added to it,
  and `touch-gestures.sh` refuses to start if any helper it calls is missing)
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

Correct portals.conf is not sufficient on its own. D-Bus activated services
inherit the D-Bus daemon's environment, not sway's, so without
`dbus-update-activation-environment` they start with no `WAYLAND_DISPLAY`.
`xdg-desktop-portal-gtk` then exits 1 immediately, because GTK cannot open a
display, and the frontend responds by dropping the FileChooser interface
entirely rather than reporting a backend failure. The symptom is every file
dialog failing with "missing xdg-desktop-portal implementation" while
`portals.conf` looks perfectly correct and the backend runs fine by hand.

`sway/config` now runs `dbus-update-activation-environment --all` at the top of
the autostart block to prevent this. To confirm it is working:

```sh
dbus-send --session --print-reply --dest=org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.DBus.Properties.Get \
  string:org.freedesktop.portal.FileChooser string:version
```

A `uint32` version means it is fine; `No such interface` means the gtk backend
failed to start.

### Session PATH and the emptty login shell

sway is started by `emptty`, which runs the session directly rather than
through a login shell, so it never reads `~/.bash_profile`. The session used to
run with `PATH=/usr/bin:/usr/sbin`, missing even `~/.local/bin`. Anything
launched from sway inherited that, so GUI apps could not find tools that worked
fine in a terminal. Zed failing to build a Rust dev extension with
`failed to run rustc: No such file or directory` was how this surfaced.

`emptty/emptty` (symlinked to `~/.config/emptty`) fixes it with emptty's
`LoginShell=/bin/bash --login` key, which starts the session under a login
shell. It replaces the stock `sway.desktop` entry and repeats its `Exec` and
`DesktopNames`. `Environment=wayland` is mandatory: emptty defaults to `xorg`.

Because `.bashrc` returns early for non-interactive shells, PATH entries the
graphical session needs must go in `shell/bash_profile`, not `shell/bashrc`.
The rustup line lives there for this reason; interactive-only additions such as
spicetify and npm-global can stay in `.bashrc`.

Check it with `tr '\\0' '\\n' < /proc/$(pgrep -x sway)/environ | grep ^PATH=`.

If a session ever fails to start, switch TTY and `rm ~/.config/emptty` to fall
back to the stock `sway.desktop`.

### Compressed swap (zram)

This machine has no swap partition or swap file, so before this any memory
spike went straight to the OOM killer with nothing to fall back on. Rust
release builds are the usual trigger: `lto = true` with `codegen-units = 1`
holds the whole program in memory at link time.

`zramen` provides compressed swap in RAM, which is a better fit than a disk
swap file on a laptop: no SSD writes, and far faster than paging to disk.

```sh
sudo xbps-install zramen
sudo ln -s /etc/sv/zramen /var/service/
```

`/etc/sv/zramen/conf` is set to zstd, 50% of RAM capped at 8 GiB, priority 100.
That yields about 6.8 GiB of swap on this 13 GiB machine; the pages inside are
compressed, so the real RAM cost when full is roughly a third of that. zstd is
chosen over the default lz4 because this is a safety net rather than routine
paging, so compression ratio matters more than raw speed.

Check it with `swapon --show`, which should list `/dev/zram0` at priority 100,
and `cat /sys/block/zram0/comp_algorithm`, where the active one is bracketed.

### VPN passwordless sudo

The VPN toggle needs `wg-quick up/down wg0` without a password. Drop a sudoers
rule **named so it sorts after `wheel`** (otherwise a broad `%wheel ALL` rule
overrides the NOPASSWD), pointing at the absolute `/usr/bin/wg-quick`:

```sh
sudo tee /etc/sudoers.d/zz-wg-toggle >/dev/null <<'EOF'
jed ALL=(ALL) NOPASSWD: /usr/bin/wg-quick up wg0, /usr/bin/wg-quick down wg0
jed ALL=(ALL) NOPASSWD: /usr/bin/wg-quick up wg-tcp, /usr/bin/wg-quick down wg-tcp
jed ALL=(ALL) NOPASSWD: /usr/bin/wg show wg0 latest-handshakes, /usr/bin/wg show wg-tcp latest-handshakes
jed ALL=(ALL) NOPASSWD: /usr/bin/ip route replace 152.69.172.139/32 *, /usr/bin/ip route del 152.69.172.139/32
EOF
sudo chmod 0440 /etc/sudoers.d/zz-wg-toggle
sudo visudo -c
```

The `wg-tcp` and `ip route` entries are for `vpn-wstunnel.sh` (see below). The
secret path it needs lives in `/etc/wstunnel/client.env`, deliberately
`root:wheel 0640` in its **own** directory rather than in `/etc/wireguard`:
that keeps the wireguard directory at `0700` while still being readable without
sudo, so the NOPASSWD rule stays narrow instead of needing blanket `grep`/`test`
as root.

### VPN and IPv6 (fail closed)

The server has **no IPv6 egress**, so global IPv6 can never go through either
transport: WireGuard has an IPv4-only `AllowedIPs = 0.0.0.0/0`, and the TCP
fallback's redsocks redirect is `iptables` only, with nothing in `ip6tables`.

On a connection with native IPv6 (Starlink) that meant v6 traffic sailed
straight out while the VPN looked connected. `curl -4` reported the Oracle exit
address, `curl -6` reported the real Starlink one, and since IP-check sites
prefer IPv6 they still showed the true location. The tunnel was up; it just
wasn't carrying the half of the traffic being tested.

Both transports now fail closed instead, rejecting global v6 while connected:

```sh
ip6tables -I OUTPUT 1 -d 2000::/3 -j REJECT --reject-with adm-prohibited
```

`2000::/3` is global unicast only, so link-local (`fe80::/10`) and ULA are left
alone and NDP/DHCPv6 keep working. It is installed by `PostUp`/`PostDown` in
`wg0.conf` (and in `wireguard/wg0.conf.template`) for WireGuard, and by
`v6_block_up`/`v6_block_down` in `scripts/vpn-proxy.sh` for the fallback.

If the bar says `vpn tcp` rather than `vpn on`, WireGuard failed to come up and
the TCP fallback took over: that is the module being accurate, not stale. The
usual cause is `/etc/wireguard/wg0.conf` still holding the template's
placeholder `Address = 10.0.0.X/24` / `PrivateKey = YOUR_PRIVATE_KEY`, which
makes `wg-quick up` fail instantly on the `ip addr add`. Check with
`sudo wg show` (empty means no interface) and confirm the key matches the peer
the server expects via `grep '^PrivateKey' /etc/wireguard/wg0.conf | cut -d= -f2- | tr -d ' ' | wg pubkey`.

### VPN connects but only raw IPs work (missing `DNS =`)

If the tunnel handshakes fine (`sudo wg show wg0` shows a recent handshake and
rising transfer) but nothing loads while `ping 1.1.1.1` still works, the live
`/etc/wireguard/wg0.conf` is missing its `DNS =` line. `wg-quick` then leaves
`/etc/resolv.conf` pointing at whatever the local network handed out, and
`AllowedIPs = 0.0.0.0/0` routes those queries into the tunnel - so a private
resolver like a school's `10.1.1.5` becomes unreachable and every lookup
black-holes while IP-literal traffic keeps working.

This bites on networks with internal resolvers (school/corporate wifi) and hides
at home, where the resolver is often reachable or public either way. Note it is
*not* the UDP-blocked case `vpn-toggle.sh` falls back for - UDP/51820 is fine
here, so the bar reads `vpn on` and the fallback never triggers.

`wireguard/wg0.conf.template` already carries `DNS = 1.1.1.1, 1.0.0.1`; the fault
is the live config having drifted from it. Confirm with
`sudo grep -c '^DNS' /etc/wireguard/wg0.conf` (0 means missing), add the line
under `[Interface]`, then re-toggle. After that `cat /etc/resolv.conf` should
show only the tunnel resolver.

The drift itself had a cause worth knowing: `install.sh` used to guard the
template copy with an unprivileged `[ -e /etc/wireguard/wg0.conf ]`. That
directory is `0700 root:root`, so `$USER` cannot traverse it and the test
reported "missing" even with the file present - meaning every single run
`sudo cp`'d the placeholder template over a working config. It now tests with
`sudo test -e`. If you hit this on an older checkout, restore from one of the
`/etc/wireguard/wg0.conf.bak*` copies, but check it has a `DNS =` line: the
backups predating this fix do not.

The general lesson for this script: any `[ -e ]` / `[ -L ]` guard on a path only
root can read must run under `sudo`, or it fails open and clobbers. Every other
privileged path it touches (`/usr/libexec/elogind/system-sleep`,
`/etc/udev/rules.d`, `/usr/local/bin`) is `0755`, so this was the only instance.

### AmneziaWG over UDP/123 (preferred on N4L)

`vpn-amnezia.sh` is the fastest transport that works on the school network, and
unlike wstunnel it is still real UDP - measured 125 Mbit/s with 0% loss over 100
pings, against TCP-over-TCP for the wstunnel tier.

It works because of two quirks of that network, both measured:

- **UDP/123 escapes the ~4-packet cap.** Twelve packets at 1/s sustained 12/12
  on 123, against 4/12 on 19302 and 24454.
- **UDP/123 inspects only the first byte**, and passes plausible NTP modes.
  Junk starting `0x55` (mode 5) got 0/12 through; `0x01` and `0x1b` got 12/12.
  Conveniently WireGuard's message types 1-4 are all valid NTP modes - which is
  why `tcpdump` renders a WireGuard handshake on 123 as `NTPv0, symmetric
  active`.

So the only thing left blocking it is the handshake fingerprint, and AmneziaWG
fixes exactly that by changing the four message-type bytes:

```ini
Jc = 0          # MUST stay 0 - see below
Jmin = 8
Jmax = 80
S1 = 0          # MUST stay 0
S2 = 0          # MUST stay 0
H1 = 27         # 0x1b - init,     NTP v3 client
H2 = 36         # 0x24 - response, NTP v4 server
H3 = 37         # 0x25 - cookie
H4 = 35         # 0x23 - transport data
```

**`Jc`, `S1` and `S2` must stay 0**, which is the opposite of AmneziaWG's usual
advice. Junk packets and junk prefixes put *random* leading bytes on the wire,
and the NTP first-byte inspector drops those. Only `H1` and `H4` travel
client-to-server, so those two are the ones that must remain NTP-plausible.

**Server side** (`server.jedbillyb.com`): the `amneziawg` DKMS module and
`amneziawg-tools` from `ppa:amnezia/ppa`, with `awg0` on `10.0.2.1/24` listening
on 51821 under `awg-quick@awg0`. Traffic arrives on UDP/123 and is redirected:

```sh
sudo iptables -t nat -I PREROUTING 2 -i enp0s6 -p udp --dport 123 -j REDIRECT --to-ports 51821
```

**Laptop side**: Void has no AmneziaWG package and the kernel (6.18) is too new
for the DKMS module, so this uses the userspace `amneziawg-go` plus
`amneziawg-tools` built from source, at `/usr/local/bin/amneziawg-go` and
`/usr/bin/awg{,-quick}`. `awg-quick` falls back to it automatically when
`/sys/module/amneziawg` is absent.

#### Remembering the transport per network

Walking the ladder from the top costs ~12s on every connect where plain UDP can
never work - and those doomed WireGuard handshakes are exactly what the school's
DPI is built to spot, so the slowest path is also the loudest. `vpn-toggle.sh`
therefore records the transport that succeeded, keyed on SSID, in
`~/.cache/vpn-toggle-transports`, and tries that one first next time. Measured on
`Karamu Devices`: **20s to connect on first use, 5s thereafter.**

It is a hint, not a pin - everything else still falls back in the normal order,
so a remembered transport that stops working just walks the rest of the ladder
and rewrites its own entry. Verified by poisoning the cache with `wg` on a
network where `wg` cannot work: it failed, fell through to `awg`, and corrected
the entry itself. Unrecognised values are ignored. Delete the file to reset.

**The hint expires after 6h** (`CACHE_TTL`), and this matters more than it
sounds. Falling back is one-way: the ladder only ever moves *down* it, so
nothing re-checks the faster transports and one bad connect pins the slowest
one that happened to work. On 2026-08-25 `Karamu Devices` was found sitting on
`ws` at **4.3 Mbit/s** while `awg` was doing **72 Mbit/s** on the same wifi -
tier 2 had failed once, days earlier, and was never tried again. Each cache line
is `SSID<TAB>transport<TAB>epoch`; past the TTL the entry is ignored and the
ladder is walked from the top, which costs one slow connect per 6h at worst.
Two-field lines from before this change read as expired.

A tier-2 failure used to be invisible for the same reason - `vpn-toggle.sh`
discards each attempt's output, so `awg-quick up` could fail for any reason at
all and the only trace was the bar quietly reading `vpn tcp`. `vpn-amnezia.sh`
now appends `awg-quick`'s own stderr to `/tmp/vpn-amnezia/diagnostics.log`
(`vpn-amnezia.sh diag`) on every `up`, failed or not.

#### Reading the waybar module

`vpn-status.sh` names the transport rather than just on/off, because
`vpn-toggle.sh` silently falls back through four of them and they are not
equivalent - measured on the school wifi, `awg` beats `ws` by 3x on a good
day and by **17x** on a bad one (72 vs 4.3 Mbit/s, 2026-08-25):

| Bar text | Transport | Colour |
|---|---|---|
| `vpn wg` | WireGuard, UDP/51820 | green - full speed |
| `vpn awg` | AmneziaWG, UDP/123 | green - full speed |
| `vpn ws` | WireGuard over TCP/443 | amber - degraded, ~33 Mbit/s |
| `vpn ssh` | SSH SOCKS + redsocks | amber - IPv4 TCP only, local DNS |
| `vpn off` | nothing up | grey |

Hover for the interface, tunnel address and endpoint. Note `awg0` is a
userspace TUN device, so it does **not** match `ip link show type wireguard` -
the module has to check for it by name, which is why it read `vpn off` while
AmneziaWG was actually connected.

#### Gotcha: server `FORWARD` rules must be inserted, not appended

The `FORWARD` chain has a catch-all `REJECT --reject-with icmp-host-prohibited`
partway down. `awg0`'s `PostUp` originally used `-A FORWARD`, which put its
ACCEPT rules *after* that REJECT where they could never match. The handshake
still completed - so `awg show` looked perfectly healthy - while every forwarded
packet came back as `From 10.0.2.1 Destination Host Prohibited`. The `PostUp`
uses `-I FORWARD 1` for this reason. The `wg0` rules happen to sit before the
REJECT, which is why the older tunnel never hit this.

#### Rolling out AmneziaWG clients

Adding a device used to be a manual grind - generate a keypair, find a free IP,
hand-edit the peer block, reload, write the client config, make a QR. `awg-client`
(in `scripts/`, deployed to the OCI server at `/usr/local/bin/awg-client`) does
the whole thing:

```
sudo awg-client add <name>            # keys + next free IP + live add, prints config & QR
sudo awg-client add <name> --split    # ...with Microsoft 365 routed outside the tunnel
sudo awg-client add <name> --file     # ...and writes <name>.conf (0600) beside you instead
sudo awg-client add <name> --ip A.B.C.D  # pick the address instead of taking the lowest free
sudo awg-client add <name> --json     # one machine-readable object, for the dashboard
sudo awg-client list                  # every peer, its IP, and last handshake age
sudo awg-client list --json           # ...plus endpoint and transfer counters
sudo awg-client del <name>            # removes it live and from the config
sudo awg-client egress list           # public/private address pool + SNAT rules, as JSON
sudo awg-client egress alloc --label X  # reserve a new public IPv4 from OCI and wire it up
sudo awg-client egress release <priv>   # hand one back to OCI
sudo awg-client egress apply          # rebuild the SNAT chain from the dashboard's plan
```

`add` bakes in the `H1-H4`/`Jc=S1=S2=0` params every client needs to clear the
UDP/123 filter. Three deliberate safety choices:

- The peer is added with **`awg set <if> peer …`, not `syncconf`/`addconf`** -
  that touches only the one peer and never re-applies the interface obfuscation
  params, so an `add` can't knock the other peers offline.
- The generated config holds the client **private key**. By default it goes to
  **stdout alone** (all chatter and the QR go to stderr) and is never written to
  disk server-side, so there is nothing to shred.
- If persisting the peer block to `awg0.conf` fails - a read-only `/etc`, a full
  disk - the **live add is rolled back**. Otherwise the interface would carry a
  peer the config file has never heard of.

`egress` is the one subcommand that is not implemented here: it execs
`/usr/local/lib/awg-dash/egress.py` (from
[`awg-dashboard`](../awg-dashboard)'s `privileged/`) with the OCI SDK's
interpreter, because the OCI API calls and the JSON they involve are miserable
in bash. It lives behind `awg-client` anyway so the sudoers rule stays a single
line. What it does: give a client its own public IPv4 by SNAT-ing it to a
secondary private address that OCI has a reserved public IP mapped onto. The
rules go in their own `AWG_EGRESS` nat chain ahead of the catch-all
`MASQUERADE`, so anything without a rule keeps the old shared-IP behaviour.

`--ip` and `--json` exist for [`awg-dashboard`](../awg-dashboard), the VPN-only
web UI, which runs unprivileged and reaches root *only* through this script via
a one-line sudoers rule. That is why every argument is validated here rather
than by the caller: `--ip` must be a free host address in `10.0.2.0/24` and
never the server, and `--file` is refused when there is no controlling terminal
(it would write a root-owned file into an unattended caller's cwd).

#### Microsoft 365 split tunnel

The tunnel egresses in the OCI region, so Microsoft geolocates every user there:
"unusual sign-in location" prompts, and region-wrong content in Teams and the
Office web apps. `awg-split-update` fixes that by generating `AllowedIPs` as
`0.0.0.0/0` **minus** Microsoft's published M365 ranges, so that traffic leaves
via the user's own connection and they appear where they actually are.

```
sudo awg-split-update              # refresh if Microsoft published a new version
sudo awg-split-update --force      # rebuild regardless
sudo awg-split-update --dry-run    # print the list and stats, write nothing
```

It writes `/etc/awg-dash/split-allowedips.txt`; `awg-client add --split` reads
that file. **The split is opt-in per peer.** Plain `add` issues a full tunnel, as
it always has, and a `--split` that cannot find a usable list falls back to a
full tunnel with a warning on stderr. A failed update therefore degrades to the
old behaviour instead of breaking provisioning, and peers you would rather keep
fully tunnelled simply never ask for it. [`awg-dashboard`](../awg-dashboard)
exposes the same choice as a per-peer checkbox. A weekly `awg-split-update.timer` (in
[`awg-dashboard`](../awg-dashboard)'s `deploy/`) keeps it current; Microsoft
revises the list roughly monthly.

Two things constrain this far more than they look:

- **Routing is decided client-side.** `AllowedIPs` lives in the client's own
  config file, fixed at the moment the config is generated. Nothing on the
  server knows or cares which mode a client is in, so switching a peer costs no
  server-side change at all - but the config *on the device* has to change. Two
  ways: hand-edit the `AllowedIPs` line in the config the device already holds
  (same keypair, fine on a desktop, miserable on a phone at 1600 bytes), or
  re-issue the peer, which mints a fresh keypair and needs a re-import. **Land
  this before a rollout** and you skip the round of re-imports.
- **The QR code sets a hard size budget.** Phones onboard by scanning, and
  `qrencode --level=M` tops out near 2331 bytes. A full tunnel is 9 bytes of
  `AllowedIPs`; a split is 120 CIDRs. Microsoft's *complete* published list
  comes to 193 CIDRs / 2975 bytes and does not fit a QR at any error-correction
  level, so four measured policies bring it to 138 CIDRs / 1861 bytes
  (a 2172-byte config, still inside a level-M QR):

  1. **Snap to parent blocks** `13.107.0.0/16`, `150.171.0.0/16`, `52.96.0.0/11`.
     The first two are Front Door anycast, so snapping them also catches the CDN
     addresses behind the 53 URL-only entries that publish no IPs at all.
     `40.96.0.0/11` is deliberately *not* snapped: only ~37% of it is M365
     (against ~69% for `52.96.0.0/11`), so it would drag unrelated Azure out of
     the tunnel, and on school wifi that means those sites meet the N4L filter
     again.
  2. **Drop stray addresses outside those blocks.** Microsoft lists a handful of
     lone `/32`s as extra addresses for hostnames whose main ranges are already
     excluded. Each one punches a deep hole in the complement and costs 14-21
     CIDRs of the budget to catch a single address.
  3. **Punch the VPN endpoint out of the tunnel** (`152.69.172.0/24`). This one
     is not about size, it is what makes a split work on `wg-quick` at all.
     With `AllowedIPs = 0.0.0.0/0`, wg-quick routes via `fwmark` plus a
     `suppress_prefixlength` rule and the tunnel's own packets escape through
     that. A split list contains no `/0`, so wg-quick instead adds one plain
     route per CIDR and sets no fwmark - and `152.69.172.139` sits inside
     `152.0.0.0/5`, so its route points into `awg0` and WireGuard tries to reach
     its own endpoint through itself. Nothing moves. A `/24` rather than the
     bare `/32` because a lone address costs ~32 CIDRs of the QR budget against
     24 for a `/24`, in the same OCI range either way. `awg-split-update`
     asserts the endpoint is **outside** the list and the `10.0.2.0/24` tunnel
     subnet is **inside** it, refusing to write otherwise.
  4. **Drop inbound mail-flow ranges** (`*.protection.outlook.com`,
     `*.mx.microsoft`). These are what a *sending mail server* talks to, never
     user traffic, so they do nothing for geolocation - and `40.92.0.0/15`,
     `40.107.0.0/16` and `104.47.0.0/17` together are precisely what pushes a
     full list past the QR limit.

  To watch the split actually happening rather than reason about it:

  ```
  vpn-split-watch [interval]     # default 2s, Ctrl-C to quit
  ```

  Two panels. **RATES** is bytes/sec down each path; `awg0`'s counters are the
  decrypted inner traffic and the direct figure is the physical interface minus
  that, so it is approximate (the tunnel's own encrypted packets cross the same
  wire) - read it as "is anything material leaving in the clear", and note it
  never reads zero. **FLOWS** is the authoritative half: every established
  connection with process, host and the path the kernel will actually use,
  asked of the routing table per destination, DIRECT rows first.

  ```
  PATH    REMOTE           PORT   PROCESS          HOST / SERVICE
  DIRECT  52.123.176.73    443    chrome           Microsoft Teams
  DIRECT  52.108.8.12      443    chrome           Office web apps
  DIRECT  152.69.172.139   443    claude           your OCI server
  VPN     10.0.2.1         443    firefox          VPN internal
  VPN     140.82.113.25    443    firefox        lb-...-iad.github.com
  VPN     172.217.25.174   443    firefox        accounts.youtube.com
  ```

  Teams, Outlook, SharePoint, Office and Entra sign-in should read DIRECT;
  everything else, including the dashboard at `10.0.2.1`, should read VPN.

  `HOST / SERVICE` is the **real TLS SNI** wherever possible: a `tcpdump` reads
  ClientHello messages on every interface and maps address to hostname, so a
  YouTube tab reads `www.youtube.com` rather than a bare `142.x`. Both cheaper
  options fail here - Google publishes no PTR for its frontends (and most
  Microsoft service IPs have none either), and passive DNS sniffing sees nothing
  because Firefox and Chrome resolve over DoH.

  SNI only exists for a **new** connection, so a flow that handshook before the
  tool started never shows one. Those fall back to the built-in label table, then
  to PTR, so nothing stays blank forever and a row can sharpen from
  "Microsoft Teams" to a real hostname once it reconnects. All three are display
  only; the PATH column always asks the kernel.

  Consequence worth knowing: reaching the server's *public* address no longer
  goes through the tunnel, because the endpoint hole covers it. `ssh oci` still
  works directly, and `10.0.2.1` remains available over the tunnel.

  `awg-split-update` **enforces the budget itself**: it runs the candidate list
  through `qrencode` and refuses to write if it would not fit, keeping the
  previous list rather than silently breaking phone onboarding. It likewise
  refuses a suspiciously short feed, or any list that would stop routing
  `10.0.2.0/24` or the server endpoint through the tunnel.

Verified against the live feed (version `2026081400`): Teams, Outlook, SharePoint
/OneDrive, the Office web apps, `portal.office.com` and Entra sign-in all resolve
to addresses **outside** `AllowedIPs` (they bypass), while Google, GitHub,
Wikipedia, Netflix and the BBC all stay **inside** it. `github.com` resolves into
Azure and still tunnels, which confirms the roundups did not over-reach. The
generated config re-decodes byte-identical from its QR with all 120 CIDRs intact.

What still rides the tunnel: the URL-only CDN entries that publish no IPs
(`*.cdn.office.net` and friends, mostly static assets), and IPv6 is untouched
because configs carry no `::/0` and so already bypass.

Getting the config onto each platform:

- **iOS / Android**: install the dedicated **AmneziaWG** app (App Store
  `id6478942365`, or Play Store - the stock WireGuard app can't speak it), then
  **+ → Scan QR** at the terminal. Import and toggle on.
- **Windows**: use **AmneziaWG for Windows**
  (`github.com/amnezia-vpn/amneziawg-windows-client` - the Amnezia fork of the
  WireGuard GUI, Wintun-based, the official/recommended Windows client; the stock
  WireGuard app silently ignores the `H`/`Jc` lines and won't handshake). It
  imports a native `.conf`, so grab a clean one and scp it over:
  ```
  ssh oci "sudo awg-client add sophias-laptop" > sophias-laptop.conf
  ```
  Because the config is the *only* thing on stdout, that redirect captures it
  with no QR or log noise. Then **Import tunnel(s) from file → Activate**, and
  delete the loose `.conf` (the app has copied the key into its own store).
  `--file` does the same server-side when you're on the box directly.

Verified end to end: adding a throwaway peer allocated the lowest free IP, went
in live (`awg show` +1 peer) and persisted; deleting it restored the config
byte-for-byte, with the other peers untouched throughout. Both the clean-stdout
redirect and `--file` were checked to produce a config starting at `[Interface]`
with no noise.

### WireGuard over TCP/443 (N4L / school wifi)

On the school network (`Karamu Devices`, N4L) plain WireGuard fails: the
handshake leaves the laptop and **reaches the server**, which answers, but the
reply never comes back. Captures on both ends confirmed it - server-side
tcpdump shows the 148-byte init arriving and a 92-byte response going out;
laptop-side tcpdump shows zero inbound packets.

This was originally recorded here as a return-path filter. **That was wrong**,
and packet-level testing on 2026-08-19/20 established what it actually is:

- A **stateful DPI fingerprints the handshake exchange**. The pair "148-byte
  type-1 out, 92-byte type-2 back" is dropped; either half alone passes 4/4.
  It matches on the message-type header bytes, not on packet sizes, and it
  behaves identically on 51820, 443, 24454 and 123 - so port-hopping alone
  genuinely cannot help, just not for the reason first assumed.
- **Unclassified UDP flows are capped at ~4 packets.** A flow gets four packets
  through and is then dropped outbound (confirmed server-side: sequence 0-3
  arrive, nothing after). A fresh source port earns a fresh allowance.
- **UDP/123 is exempt from that cap** and sustains traffic indefinitely, which
  is what makes the `vpn-amnezia.sh` transport (documented above) possible.

Two other things that network does, both proven with `dig`:

- **All UDP/53 is transparently hijacked** to its own resolver.
  `dig @192.0.2.1 google.com` - an address that cannot possibly answer -
  returns a valid response, and `dig @1.1.1.1 id.server TXT CH` comes back as
  `AkamaiRecursive_...`, not Cloudflare. So UDP/53 is useless as a transport.
- **SafeSearch is forced via DNS**: `www.google.com` resolves to
  `forcesafesearch.google.com`.

`vpn-proxy.sh` works there but is only a proxy - IPv4 TCP via redsocks, with DNS
left on the local resolver. `vpn-wstunnel.sh` is the real fix: actual WireGuard
inside a WebSocket over TCP/443, so UDP and DNS tunnel too. `vpn-toggle.sh`
tries UDP first, then this, then the SSH proxy.

**Server side** (`server.jedbillyb.com`): wstunnel listens on `127.0.0.1:8099`
(not 8443 - Pelican `wings` already holds that) under `wstunnel.service`, and
nginx reverse-proxies a secret path on the existing 443 vhost to it. The path
*is* the credential; wstunnel is additionally `--restrict-to 127.0.0.1:51820`
so a leaked path cannot forward anywhere else. Sharing 443 with the real sites
means valid certs and ordinary-looking HTTPS.

**Client side**: `/etc/wireguard/wg-tcp.conf` points its peer `Endpoint` at the
*local* wstunnel listener, `127.0.0.1:51821`.

Two settings in that config are load-bearing:

- `MTU = 1280`. WireGuard inside WebSocket/TLS/TCP carries far more overhead
  than a plain UDP tunnel, so wg-quick's default 1420 blackholes full-size
  packets while small ones still pass.
- The `PostUp` host route for the server IP. Without it wstunnel's own TCP
  connection gets routed into the tunnel it is carrying and deadlocks instantly.
  It works because wg-quick's `suppress_prefixlength 0` rule lets specific
  routes in the main table still win over the tunnel default.

#### A handshake is not proof the tunnel works

`vpn-wstunnel.sh up` verifies three layers independently before keeping the
tunnel - HTTPS by IP, DNS, then HTTPS by name - and reports which failed. It
also arms a **detached watchdog** before anything captures the default route:
if confirmation never arrives within 45s the tunnel is torn down automatically.

This exists because the first working build handshaked fine, passed ICMP, and
resolved nothing - which needed a reboot to recover. Tearing down only on a
failed *handshake* is not enough; a tunnel can be up and useless. `diag` dumps
the state captured at failure (routes, rules, resolver, an MTU probe, wstunnel
log) so a failure is debuggable after the tunnel is already gone.

#### Gotcha: port-hopping REDIRECTs must be scoped to the public interface

The server also accepts WireGuard on UDP/443 redirected to 51820, and UDP/123
redirected to 51821 (`awg0`), for networks that block 51820 but allow those. The
53/500/4500 redirects were removed - the OCI security list never allowed those
ports inbound, so they could not fire. The rules **must** carry `-i enp0s6`:

```sh
sudo iptables -t nat -I PREROUTING 1 -i enp0s6 -p udp --dport 53 -j REDIRECT --to-ports 51820
```

Without `-i`, `nat PREROUTING` also matches traffic being forwarded *out of*
`wg0`, so every VPN client's DNS query to `1.1.1.1:53` gets hijacked back into
the wireguard port. Symptom: the tunnel works for everything except name
resolution, for every client at once. (These need matching OCI security-list
ingress rules to be reachable at all - 443 and 51820 were already open, and
123/19302 were added on 2026-08-20.)

### AirPods battery module

`waybar/airpods-status.sh` is a symlink into the
[waybar-airpods](https://github.com/jedbillyb/waybar-airpods) repo, following the
same convention as the AirDrop module: the script lives with the project that
owns it, this repo only carries the link and the waybar wiring.

### Heat pump module

`waybar/heatpump-status.py` is a symlink into the
[waybar-heatpump](https://github.com/jedbillyb/waybar-heatpump) repo, same
convention as the AirDrop and AirPods modules. It talks ECHONET Lite (UDP
3610) to the lounge heat pump: the bar shows room temperature coloured by
mode (amber heating, blue cooling, grey idle, red on a fault), the tooltip
carries setpoint, outdoor temperature, fan speed and lifetime kWh.

Left click opens an eww control panel (setpoint steppers, mode buttons, fan
bar); right click toggles power. The device address and the unit's real
maximum fan speed live in `~/.config/waybar/heatpump.conf`, which is
deliberately *not* tracked here - it is per-house, and this is a public
checkout.

Scroll bindings were tried and removed: a scroll gesture that lands on the
module walks the setpoint to the end of its 16-31°C range, which in heat mode
reads as the unit having switched itself off.

It shares the `padding: 0 10px` rule with every other module rather than
carrying its own. Left off that list it had no padding at all, which made the
gap between it and the AirPods module roughly half the gap everywhere else -
and narrow enough that the panel's position detector could no longer tell the
two modules apart.

The AirPods module sits immediately to its left in `modules-right`, so the heat
pump module is no longer the leftmost item in the right-hand group.

### Laptop battery colour

The `battery` module (not to be confused with the AirPods module above) uses
waybar's built-in `states` thresholds — `warning` at 30%, `critical` at 15%,
`urgent` at 5% — to add `.warning`/`.critical`/`.urgent` CSS classes, plus
the automatic `.charging` class. `waybar/style.css` colours these: grey by
default, amber under 30%, red under 15%, green while charging (charging
colour wins over the level colour). Under 5% and unplugged, the pill flashes
red/transparent via `@keyframes` instead of just recolouring — GTK3's CSS
engine (what waybar renders with) has no `:has()`/parent selector, so this
can't reach up and flash the whole bar, only the battery module itself. GTK
CSS is also pickier than real CSS: no comma-grouped keyframe selectors
(`0%, 100%` fails to parse) and `steps()` only accepts `start`/`end`, not
`jump-none`.

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

### KDE Connect

`exec kdeconnect-indicator` in the sway config. The indicator spawns
`kdeconnectd` itself and adds a tray icon next to nm-applet and blueman-applet,
so one line covers both the background daemon and the GUI you open when you
actually want to send something. `kdeconnect-app` and `kdeconnect-cli` are there
for the full UI and for scripting.

Plain `exec`, not `exec_always`. A sway reload would otherwise leave a second
indicator fighting the first for the tray slot.

No firewall rules are needed on this machine: KDE Connect wants TCP+UDP
1714-1764 and the `INPUT` policy here is `ACCEPT` with no nft or ufw ruleset.

Discovery is a UDP broadcast, so both devices have to sit on the same layer-2
segment. Two local consequences:

- Bring **wg0 down before pairing**. The full-tunnel VPN routes the broadcast
  out to the OCI endpoint instead of across the LAN.
- It will not work on the school's N4L "Karamu Devices" SSID, which has client
  isolation. Home WiFi is fine.

Paired against an iPhone the feature set is thin: no clipboard sync, no run
commands, no real file browsing, and notification sync is one-way and flaky.
Phone notifications on this machine come from ANCS over Bluetooth instead (next
section); KDE Connect is here for file transfer and remote input, not
notifications.

### iPhone notifications over Bluetooth (ANCS)

iOS notifications mirror to this machine over BLE using Apple Notification
Center Service, the same protocol a smartwatch uses. No app on the phone and no
jailbreak. The client is [ancs4linux](https://github.com/pzmarzly/ancs4linux),
cloned to `/mnt/shared/projects/ancs4linux` and run from its own venv:

```sh
cd /mnt/shared/projects/ancs4linux
python3 -m venv --system-site-packages .venv && .venv/bin/pip install .
```

`--system-site-packages` matters: PyGObject comes from `python3-gobject`, not pip.

The role is inverted from what you would guess. This machine advertises as a BLE
*peripheral* carrying the ANCS solicitation UUID; the iPhone connects to it, and
only then does this machine become the GATT *client* that reads notifications
off the phone. That is why the advertising daemon has to keep running after
pairing - a bonded iPhone only reconnects to a peripheral that is advertising.

Three daemons, split by which bus they need, plus two local helpers:

| Daemon | Bus | Started by |
| --- | --- | --- |
| `ancs4linux-observer` | system | runit, `/etc/sv/ancs4linux-observer` |
| `ancs4linux-advertising` | system | runit, `/etc/sv/ancs4linux-advertising` |
| `ancs4linux-desktop-integration` | session | `exec` in sway/config |
| reconnect poller | - | runit, `/etc/sv/ancs4linux-reconnect` |
| advert/observer watchdog | - | runit, `/etc/sv/ancs4linux-watchdog` |

Upstream ships systemd units, which are useless here. The runit `run` scripts
live in `ancs4linux/sv/` in this repo and `install.sh` copies them into
`/etc/sv`. They cannot be symlinks - runit reads `/etc/sv` at boot, before
`/mnt/shared` is mounted - and for the same reason each script spins waiting for
its binary to appear rather than failing into a restart loop.

Advertising is off until something asks for it over D-Bus, so the advertising
service re-arms it on every start:

```sh
ancs4linux-ctl enable-advertising --hci-address <hci> --name <hostname>
```

The two system daemons own bus names that `/etc/dbus-1/system.d/ancs4linux-*.conf`
restricts to root and the `ancs4linux` group. `desktop-integration` runs as you,
so your user must be in that group - and because group membership is only picked
up at login, it will fail with a D-Bus policy denial until you log out and back
in.

**The advertisement dies silently, and the watchdog is what puts it back.**
This is the failure mode that looks least like a failure. Every service reads
`run:` and the advertising daemon logs nothing wrong, but the controller is
broadcasting nothing at all, so the bonded phone has no peripheral to reconnect
to and simply stays away. Observed 2026-08-19 with the daemon up 8h47m; the
likely trigger is suspend/resume, since the advertising service enables the
advert exactly once at boot and nothing ever re-arms it.

Check it with `btmgmt advinfo`, never `bluetoothctl`:

```sh
sudo btmgmt advinfo | tail -3   # want "Instances list with 1 item"
```

`bluetoothctl show` has been seen reporting `ActiveInstances: 1` for an advert
the controller had already dropped, so it is not evidence.

`ancs4linux-watchdog` polls that every 30s and re-arms when it reads zero. It
also restarts the observer on the phone's disconnected -> connected edge,
because that resubscribe never happens on its own (see below). To do it by hand,
note that **`enable-advertising` has to be called twice**: the first call fails
with a rich-formatted traceback ending in `DBusError: Does Not Exist`, which is
expected rather than a real error. The daemon still has the adapter in its
in-process `active_advertisements` dict, so it tries to tidy up with
`UnregisterAdvertisement` on an advert BlueZ no longer has. That dict entry is
deleted before the throw, so the second call takes the clean path and registers
for real. Always follow with `disable-pairing` - `enable-advertising`
re-registers ancs4linux's own agent as the system default agent, and that agent
consents to any bond without really asking.

**After re-pairing, restart the observer.** Re-pairing gives the phone new GATT
object paths, and the observer keeps its old view - its debug line reports
`paired connected not-communicator`, and it sits there with `connected` false
while `bluetoothctl` says the device is connected. It never re-subscribes, so
the phone looks connected but no notifications arrive:

```sh
sudo sv restart ancs4linux-observer
```

**The phone does not reliably reconnect on its own.** It is supposed to: a
bonded iPhone reconnects to a peripheral it sees advertising. In practice, after
a reboot or an advertising restart, it sat disconnected indefinitely with
advertising up, and one outbound `bluetoothctl connect` brought it straight back
with ANCS resubscribing immediately. Hence the reconnect service, which polls
every 60s for bonded devices whose name looks like an iPhone or iPad and
connects any that are disconnected. Make sure the phone is **trusted**
(`bluetoothctl trust <mac>`) too, or BlueZ wants authorisation for the incoming
connection and there is no longer an agent standing by to give it.

That poller cannot rescue a classic-led bond, which is the usual state. The
iPhone's device record carries A2DP/HFP/NAP plus a LinkKey, so BlueZ routes
`Device1.Connect()` over BR/EDR and will not fall back to LE, and iOS only
accepts an inbound classic connection while its Bluetooth settings screen is
open. Every attempt returns `br-connection-unknown`. The run script used to
discard that error with `|| true` and log an unconditional `reconnecting ...`,
which made a service that had never once succeeded look healthy; it now logs the
real outcome, de-duplicated so a failure repeating for hours is logged once.
When it is stuck there, recovery is on the phone: open Settings > Bluetooth and
tap the laptop so iOS initiates.

**Renaming does not propagate.** iOS caches the GAP name it learned at pairing
time and will keep showing the old one - changing the adapter alias or the
advertised name does nothing to an already-paired entry. Forget the device on
the phone and pair again.

**ancs4linux does not solicit the ANCS UUID, and must be patched to.** Its
advertisement carries no service UUIDs at all. Soliciting
`7905f431-b5ce-4e99-a40f-4b1e122d00d0` is how a smartwatch announces that it
wants notifications, and it is what makes iOS classify the peripheral as a
notification accessory. Without it the failure is silent and deeply
misleading: pairing works, the GATT subscribe reports success, and iOS simply
never sends a thing - with no "would like to access your notifications" prompt
at pairing and no Show Notifications toggle in the device's info screen to turn
on afterwards. `patches/ancs4linux-solicit-ancs-uuid.patch` adds it.

Note that the venv is built with `pip install .`, not `-e`, so the daemons run
from the copy in `site-packages`. Editing the checkout changes nothing until:

```sh
cd /mnt/shared/projects/ancs4linux
.venv/bin/pip install --force-reinstall --no-deps .
sudo sv restart ancs4linux-advertising ancs4linux-observer
```

**Pairing.** Unpair on both ends first if the phone was ever paired, then let
advertising come up, and on the phone open Settings -> Bluetooth and tap this
machine under Other Devices. ANCS needs a real BLE bond, and a plain BR/EDR
pairing only produces one via cross-transport key derivation, so a fresh pair is
what makes it work. `Asking for notifications: success` in the observer log is
the confirmation. Advertising takes up to 30 seconds to settle; connecting
before it does will fail.

**The pairing agent is unregistered on purpose.** Enabling advertising makes
ancs4linux register its own agent as the system *default* agent, and that
agent's `RequestConfirmation` is a no-op:

```python
def RequestConfirmation(self, device: ObjPath, passkey: UInt32) -> None:
    self.server.emit_pairing_code(str(int(passkey)))
```

Returning from `RequestConfirmation` is how BlueZ is told "the user said yes" -
rejecting means raising. So it emits the passkey as a notification and accepts
unconditionally. The "Pair if PIN is 123456" popup is cosmetic; the code always
matches because nothing ever compares it, and you are bonded before you read
it. With advertising running permanently under runit, that agent would sit
registered as the default forever, accepting any pairing request in range.

So the advertising run script calls `disable-pairing` right after
`enable-advertising`, and **nothing here ever turns it back on** - including
during pairing, which is the one moment it would matter. There is deliberately
no time-limited "pairing window" either: a window bounds *how long* an
auto-accepting agent is exposed rather than removing it, and the exposure would
still cover exactly the period when someone is trying to pair.

`scripts/bt-pair-agent.py` handles pairing instead, started from sway/config.
It advertises **DisplayYesNo**, so BlueZ negotiates Numeric Comparison: both
sides show the same six-digit code and this laptop asks you to confirm it
matches, in a **swaynag** bar with Accept/Decline - the same prompt style as the
AirDrop receive confirmation.

**`DisplayYesNo` is mandatory, and this is not a free choice.** The stronger
scheme - `KeyboardOnly`, where the phone displays a code and you *type* it on
the laptop - was implemented, and it silently breaks ANCS. That capability makes
the host look like a keyboard-class accessory, so iOS bonds classic BR/EDR led
(a `[LinkKey]` turns up in `/var/lib/bluetooth/<adapter>/<phone>/info` next to
the LE keys) and files the laptop as an ordinary accessory. iOS then never
offers the *"would like to access your notifications"* prompt and there is no
Show Notifications toggle under Settings > Bluetooth > (i) at all. Nothing
errors: the observer reports `Asking for notifications: success` and then
receives zero events forever. If notifications stop, check the bond for
`[LinkKey]` first - that is the tell for a classic-led bond.

So the tradeoff is forced rather than chosen:

| | Attacker needs | Defeated by | ANCS |
| --- | --- | --- | --- |
| Laptop asks, you type (`KeyboardOnly`) | to *type on* the laptop | physical access to the keyboard | **broken** |
| Both show, you confirm (`DisplayYesNo`) | to be at the laptop to press `y` | someone confirming carelessly | works |

What still fixes the original bug is that the confirmation is *real*. Upstream's
flaw was never Numeric Comparison itself - it was that its `RequestConfirmation`
returned unconditionally without asking anyone. Expect the code to always match:
both sides derive it from the same exchange, so a legitimate pair can only ever
agree. It is a man-in-the-middle check, not an authorisation code, and the phone
side is meant to be a plain "yes, same number". The gate that stops a stranger
tapping Pair is *this* side's prompt, which refuses unless somebody at this
machine presses Accept. The agent refuses every other method (`DisplayPasskey`,
`RequestPasskey`, and the legacy PIN methods) rather than let a remote device
negotiate its way down to a one-click bond.

The prompt is `swaynag`, matching `airdrop-confirm` in airdrop-mt7921 and for the
same reasons: it ships with sway so it is always present, it draws its own
surface, and it needs no notification daemon - `notify-send` would exit 0 having
shown nobody anything, the worst failure mode for a consent prompt. It fails
closed too: no Wayland session, no swaynag, or no answer within 45s all mean
refuse. The one subtlety inherited from `airdrop-confirm` is that
`--button-dismiss-no-terminal` dismisses the bar *before* running its command
from a detached child, so the answer is read from per-button marker files with a
grace period after swaynag exits - never inferred from swaynag having quit.

The agent marks a device trusted once it is bonded. Without that BlueZ wants
authorisation for every incoming connection, and since this agent is the only
one registered, an unattended reconnect after a reboot has nobody to answer and
notifications simply stop.

The agent also re-asserts `RequestDefaultAgent` every 30s. Whoever calls it last
wins, sway starts blueman-applet and the agent with no ordering between them,
and blueman re-registers whenever it restarts - losing that race silently
downgrades pairing back to a one-click dialog.

The adapter stays **discoverable and pairable indefinitely**, so anything can be
paired at any time without preparing the machine first, and so the phone can be
forgotten and re-paired freely when testing. That is only reasonable because
the passkey prompt is a real barrier - a pairing attempt from across the room
cannot get past it, so leaving the door visible costs nothing. Both
`DiscoverableTimeout` and `PairableTimeout` default to non-zero and are pinned
to 0 in `/etc/bluetooth/main.conf` and again by the advertising service.

Classic discoverability is **required**, not incidental: iOS will not list this
host under Settings > Bluetooth > Other Devices from the LE advertisement alone,
so with it off there is nothing to tap and no bond can be formed. It coexists
with LE advertising fine. The advertising run script sets the
discoverable/pairable flags *before* calling `enable-advertising`, since
ancs4linux applies its `HciState` and registers the advertisement last.

When the phone cannot see the laptop, `bluetoothctl show` is not evidence - it
reports bluetoothd's *requested* state. **`sudo btmgmt advinfo` is the ground
truth**, printing `Instances list with N items` for advertising instances
actually on the controller; `ActiveInstances: 0x01` alongside `0 items` means
nothing is being broadcast. Sample it ~20s after a restart: the run script does
its setup in a backgrounded subshell, and reading it too early shows a
legitimate 0 that looks like a fault. `btmgmt info` current-settings is likewise
unreliable for `connectable`/`discoverable` - it has read as missing
`connectable` on a machine with three working bonded audio devices. Do not
"correct" it with `btmgmt discov on`; that forces classic discoverability
straight back into a classic-led bond.

`ancs-pair.sh` is then only a check that the agent is up and ancs4linux's is
not.

Dropping ancs4linux's agent gives up the reason it exists upstream - it was
there to stop the phone redirecting its audio here. That is a fine trade for a
pairing prompt that means something.

### Notification modes

The `notif` module in the bar cycles three modes on click, via
`waybar/notification-status.sh`:

| Mode | Bar | Behaviour |
| --- | --- | --- |
| `notif all` | grey | everything shows |
| `notif phone` | amber | iPhone only; local apps suppressed |
| `dnd` | red | nothing shows (still recorded in dunst history) |

`dnd` is just `dunstctl set-paused`. iPhone-only is not a dunst feature - dunst
has no way to negate a rule match, so it takes the two rules at the bottom of
`dunstrc`: `mute_local` skips everything, and `allow_iphone` un-skips anything
whose appname matches `*iPhone*`, winning because dunst applies rules in file
order and the last match wins. ancs4linux sets appname to
`<iOS app> (<device name>)`, so the device-name suffix is the only thing
distinguishing a phone notification from a local one.

The mode is remembered in `$XDG_RUNTIME_DIR/notification-mode`, so it resets to
`all` on reboot. If dunst gets paused behind the script's back, the script
believes dunst rather than its own state file.

### Popup placement

`origin = top-right` with `offset = 10x10`, so the popup's corner lands exactly
on the *visible* corner of a tiled window.

**10, not 5.** sway/config sets `gaps outer 5` **and** `default_border pixel 5`,
and those borders are fully transparent (`client.*` colours are `#00000000`), so
5px of every window is invisible and its content starts 10px in. Matching the
5px gap makes the popup overhang every window by 5px, which is what "the border
is the problem" turned out to mean. Measured against a real foot window: content
begins at `screen_width - 10` and at `y = 26`, and the popup's frame now lands on
exactly those pixels.

**dunst's vertical offset is measured from the bottom of waybar's exclusive
zone, not from the top of the screen.** The bar's own 16px height is already
excluded, so the original `10x26` (16 + 10, "bar height plus the gap") pushed the
popup a full bar-height too low while the right edge stayed correct - the
asymmetry that started this. Do not re-add the bar height here.

Internal `padding` and `horizontal_padding` are both 10. Unequal values (they
were 9 and 11) sit the text closer to one edge than the other, which reads as
the popup being misaligned even when its outer gaps are pixel-identical.

### Device name

Three separate names, all set to **Jeds Linux Laptop**, none of which is the
hostname (`void-btw`, unchanged):

| Where | Set by | Default if unset |
| --- | --- | --- |
| Bluetooth device list | `bluetoothctl system-alias`, in `install.sh` | hostname |
| BLE advertisement (ANCS) | `BT_NAME` in the advertising run script | whatever `--name` was last passed |
| AirDrop share sheet | `AIRDROP_NAME` in `airdrop/config` | `socket.gethostname()` |

No apostrophe deliberately: OpenDrop substitutes the AirDrop name into an
OpenSSL certificate subject (`/CN=<name>`) when generating its TLS identity.

Notification previews follow the phone's own **Show Previews** setting - if it
is set to "When Unlocked", locked-phone notifications arrive here with no body
text. The onboard MediaTek adapter handles ANCS fine, which is not a given;
some Realtek adapters fail the key negotiation.

### Stopping the iPhone routing its audio here

The phone is paired for notifications, but iOS also saw the laptop's **A2DP
Sink / HFP Handsfree** records and offered it as a speaker, so music and calls
got grabbed by the laptop whenever the phone connected - wireplumber put the
phone's card on the `audio-gateway` (A2DP Source & HSP/HFP AG) profile and
audio followed.

`wireplumber/wireplumber.conf.d/51-no-phone-audio-sink.conf` drops the
**sink-side** Bluetooth roles from the bluez monitor:

```
bluez5.roles = [ a2dp_source bap_source hsp_ag hfp_ag ]
```

The laptop is the *source* / audio gateway for its own headphones (AirPods,
WH-1000XM5), so those roles are all kept and headsets are unaffected. What goes
away is `a2dp_sink`, `bap_sink`, `hsp_hs` and `hfp_hf` - the roles that let
another device push audio *into* the laptop. After this the phone's bluez card
disappears entirely and the laptop no longer appears in the phone's audio
output list. Confirm with:

```sh
bluetoothctl show | grep -iE 'UUID: (Audio|Handsfree|Headset)'
```

which should list **Audio Source**, **Headset AG** and **Handsfree Audio
Gateway** and no Sink/HS/HF entries.

The same file also pins the phone's card to the `off` profile by name, as a
second layer in case the sink roles ever come back - `device.profile` takes
absolute priority in wireplumber's `find-best-profile.lua`. Note the phone's
MAC is hardcoded in that rule.

The BLE/ANCS notification link is untouched by any of this: it is a GATT
connection and does not involve the audio profiles at all.

A one-off, non-persistent version of the same fix is:

```sh
pactl set-card-profile bluez_card.B8_90_47_64_83_CB off
```

wireplumber saves that to `~/.local/state/wireplumber/default-profile`, but
state files get rewritten, hence the config above.

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

### 2.4 GHz, Bluetooth and the mt7921 combo chip

The onboard `mt7921e` is a combined WiFi + Bluetooth part, and both radios share
the 2.4 GHz front end. `ancs4linux` keeps a BLE link to the iPhone up permanently
for notifications, so on this laptop 2.4 GHz WiFi is essentially always competing
with Bluetooth.

Measured 2026-08-23, same room, minutes apart, nothing else changed:

| | 2.4 GHz | 5 GHz |
|---|---|---|
| throughput | **0.00 Mbit/s** | **80.98 Mbit/s** |
| ping 1.1.1.1 | 143 ms avg, 20% loss | 21.7 ms avg, 0% loss |
| arping the router | 452 ms median | 5.1 ms median |
| link | re-associating every ~60 s | stable |

The home AP publishes one SSID on both bands, so band steering hands the client
back to 2.4 GHz whenever 5 GHz gets weak - which happens just by walking around,
since 5 GHz measured -32 dBm near the router and -75 dBm further away. The result
looks exactly like an ISP fault: the connection dies, comes back, and dies again,
with excellent signal the whole time.

`waybar/wifi-band.sh` makes the band visible (amber on 2.4 GHz, green on 5 GHz)
and clicking it cycles the NetworkManager `802-11-wireless.band` preference
through auto -> `a` (5 GHz) -> `bg` (2.4 GHz). Pinning to 5 GHz is the fix. If the
pinned band has no usable AP the script reverts to the previous setting and
reconnects rather than leaving the machine offline.

The other half of the fix is `waybar/bluetooth-status.sh`, which toggles the
controller. Turning Bluetooth off frees the radio, at the cost of iPhone
notifications and any headset audio - hence a deliberate click, not automatic.

**It toggles rfkill, not `bluetoothctl power off`, and that is not incidental.**
Power-off does not stick here: three things race to switch the adapter back on
within a minute.

- `ancs4linux-watchdog` re-arms the BLE advert every 30s, and its
  `bluetoothctl discoverable on` powers the controller as a side effect
- `ancs4linux-reconnect` runs `bluetoothctl connect` on the bonded iPhone
  every 60s
- `/etc/bluetooth/main.conf` sets `AutoEnable=true`

A soft rfkill block sits underneath all three - BlueZ cannot power up a blocked
controller - so the toggle holds. Verified off for 100s across three watchdog
cycles, where a plain power-off came back inside a minute.

While blocked, `ancs4linux-watchdog` logs a failed re-arm every 30s to
`/var/log/ancs4linux-watchdog`. That is expected, and is not evidence of a fault
when Bluetooth is deliberately off.

**Diagnostic trap worth remembering:** `arping` to the router was 3.1 ms on
2.4 GHz while throughput was 0.22 Mbit/s. Low latency on tiny frames does *not*
prove a link can carry throughput under coexistence. Always measure throughput
per band before blaming the ISP.

### WiFi recovery after AirDrop/AWDL testing

`$mod+Shift+r` reloads the sway config, re-probes a wedged touchpad, and runs
`wifi-recover.sh`, which is meant to always be able to get the network back
however AirDrop/AWDL testing left it. Restarting NetworkManager alone is not
enough: most of the damage is below it, in the driver and the kernel's netdevs,
and NetworkManager cannot associate through any of it. The three layers are:

1. `airdrop-helper wifi-reset` (from the airdrop-mt7921 repo) - monitor and
   P2P-GO vifs, mt76 `runtime-pm`/`deep-sleep`, rfkill, interface up.
2. `wifi-recover-root` (this repo) - everything that does not cover: an owl
   still running under its repo name, a stranded `awdl0`, an rfkill soft block
   when layer 1 is absent (see below), the regulatory domain left where a run
   set it, the managed interface left in monitor type, mt76 power management
   when debugfs is unmounted (layer 1 mounts it in `up` but not in
   `wifi-reset`, so both knob writes fail silently), and NetworkManager or
   avahi-daemon still stopped because an `airdrop.sh` run was killed before its
   exit trap.
3. `nmcli` as the desktop user - radio on, networking on, interface managed,
   autoconnect back on, and a reconnect **only** if it is not already
   connected.

Every step is conditional, because this binding also fires on plain config
reloads with nothing wrong - it must never bounce a healthy association.

#### The rfkill block is usually not AirDrop's fault

`rfkill unblock wifi` sits in both layer 1 and layer 2 on purpose. Layer 1 has
it, but layer 1 lives in the airdrop-mt7921 repo, so on a machine without that
repo nothing would clear a block at all - and the common cause has nothing to
do with AWDL testing. `ideapad_laptop` registers its own `ideapad_wlan` switch
next to the mt7921's `phy0`:

```
0: ideapad_wlan: Wireless LAN     <- platform switch
3: phy0: Wireless LAN             <- the actual radio
```

rfkill ORs blocks across devices, so an Fn/airplane key event or a stale EC
state after resume soft-blocks the platform switch and drags a perfectly
healthy radio down with it. `unblock wifi` covers both devices at once.
Bluetooth is deliberately left alone - this recovery is about the network.

The module's `hw_rfkill_switch` parameter is `N` here, so it never asserts a
*hard* block; everything seen so far has been a soft block, which is why
unblocking is enough and blacklisting `ideapad_laptop` (which would also cost
the extra buttons, battery hook and platform profile) is not needed.

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

### Screen mirroring to a TV (Miracast)

`$mod+Shift+m` launches **gnome-network-displays**, which casts this screen to a
Miracast sink - the same thing Win+K does on the Windows partition.

It is Wi-Fi Direct (Wi-Fi P2P), *not* a network protocol: the laptop talks to
the TV radio-to-radio, so it works on a guest/captive network where the TV and
laptop cannot route to each other, and client isolation doesn't matter. The
MT7921 advertises `P2P-client`, `P2P-GO` and `P2P-device`, and NetworkManager
exposes the radio as a separate `p2p-dev-wlp2s0` device, so nothing special is
needed to enable it. On a Samsung set the receiver is the tile named
**Link to Windows** (or "Screen Mirroring" in the source list) - the name is
Samsung's branding, the protocol underneath is plain Miracast and a Linux
sender is fine.

The packages, none of which are pulled in automatically:

```sh
sudo xbps-install -S gnome-network-displays \
    gstreamer1-pipewire gst-plugins-good1 gst-plugins-ugly1 gst-libav
```

The two that actually bite:

- **`gstreamer1-pipewire`** provides `pipewiresrc`, which is how the app gets
  the screen out of the portal. Without it the sink is discovered and the
  connection is made, then nothing is ever sent.
- **`gst-plugins-good1`** provides `rtpmp2tpay` and `udpsink`. The rest of the
  pipeline (`mpegtsmux`, `openh264enc`) lives in `gst-plugins-bad1`, which was
  already installed, so the failure looks like a half-working install.

`vah264enc` is available on this machine, so encoding is done on the GPU rather
than by `openh264enc` on the CPU.

Discovery takes about five seconds after the window opens. If the TV never
appears, check that the P2P device exists and is idle rather than blaming the
app:

```sh
nmcli device | grep wifi-p2p    # expect: p2p-dev-wlp2s0  wifi-p2p  disconnected
```

NetworkManager's P2P support requires the **wpa_supplicant** backend; it does
not exist under iwd, so switching the backend silently removes Miracast.

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

### Tap-to-click

The `input type:touchpad` block only set `natural_scroll`, so tap-to-click
fell back to libinput's default of disabled. `tap enabled` is now explicit
in the config.

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
| **2 fingers**, in from the **right/left** edge | Step one workspace by number, creating it |
| **2 fingers**, up from the **bottom** edge | Spotlight launcher |
| **2 fingers**, down from the **top** edge, 180px or more | Close the focused window |
| 1 finger, near a window boundary (not on an edge) | Drag that boundary (see below) |

`workspace next_on_output` only walks the workspaces that already **exist**, so
there is otherwise no way to swipe to somewhere blank and start something in it —
which matters much more without a keyboard than with one. The same edge swipe
with **two fingers** runs `scripts/workspace-step.py`, which walks the *numbers*
instead: from 3 it goes to 4, and back to 3, creating whatever is missing. One
finger might jump 3 → 9; two fingers never will. It does not skip an occupied
number looking for a free one — asked for 5, you get 5, empty or not.

**This started as a long one-finger swipe, and measuring is what killed the
idea.** lisgd's distance buckets are thirds of the screen, so `L` wanted 1267px
horizontally — but real "long" swipes here measured 401–579px, *the same range as
ordinary edge swipes*. No threshold separates two gestures that are not actually
different lengths. A finger count is different, and needs no guard at all.

An earlier version also skipped to the nearest unused number and refused to move
while already on an empty workspace. Both were wrong in use: stepping back and
forth behaved differently depending on what happened to be open.

**One finger navigates what already exists; two fingers do everything else.**
That split is forced, not stylistic. Scrolling is a one-finger drag, and lisgd's
edge test looks at *both* ends of a swipe, so a one-finger scroll near a screen
edge simply *is* these gestures:

| what you are doing | what lisgd sees |
| --- | --- |
| scroll down a page | swipe up, starting near the bottom → the launcher |
| scroll up a page | swipe down, starting near the top → close the window |

Both were bound to one finger, and both fired while reading email. No distance
guard fixes it — a real scroll runs 200–500px, well past anything low enough to
leave the gesture usable. It is the same lesson as the long-swipe attempt above:
**a threshold cannot separate two gestures that are the same gesture.** A finger
count can, because scrolling never uses two.

Close-window additionally carries a distance guard (**180px**), being the only
destructive gesture — two fingers *and* a deliberate drag, not two fingers
alone. The launcher needs none. Anchoring both to an edge also matters for a
second reason, described under "a pressed gesture can decline" below.

180 is a pixel count rather than one of lisgd's buckets, which needed
`patches/lisgd-distance-px.patch`. The buckets are thirds of the screen, so the
only guards available for a downward swipe were "any distance" and "at least
396px" — and real close swipes here measure **262–309px**. `M` was therefore
unreachable in practice: the gesture registered perfectly every time, correct
direction and correct edge, and was discarded on distance. 180 sits deliberately
*below* that measured range, because a guard set at the bottom of what you
currently do is one you will miss the moment you are in a hurry, and the failure
is silent.

Nothing is bound to three or four fingers. A release gesture only counts the
fingers whose *own* swipe matched, and with three or four down one of them
almost always drifts off direction, so the count falls short and nothing
happens.

Dropping them is what makes the loose recognition below safe — switching
workspace, opening the launcher and resizing are all reversible, so a stray
match costs a swipe back.

`-t 15` is how far a swipe must travel to count at all (~2.7mm here). It can
afford to sit low because everything bound to a release gesture is reversible — a
workspace step costs a swipe back — and the one destructive gesture does not rely
on it, carrying its own 180px guard instead.

Distance was never what made a swipe fail to *register*, though — three other
defaults were, and all three are loosened:

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

Four local patches are needed, in this order. Reapply after any lisgd update, or
touch resize silently stops working and gestures start eating each other:

```sh
cd /mnt/shared/projects/lisgd
for p in lisgd-export-gesture-coords \
         lisgd-cardinals-before-diagonals \
         lisgd-pressed-decline \
         lisgd-distance-px; do
  git apply /mnt/shared/projects/dotfiles/patches/$p.patch
done
make WITHOUT_X11=1 && install -m755 lisgd ~/.local/bin/lisgd
```

The first exists because upstream lisgd does not tell the command *where* the
gesture started — it calls `system()` and nothing else. It adds `LISGD_X` /
`LISGD_Y` (and `LISGD_CUR_X` / `LISGD_CUR_Y`) to the environment first,
capturing them before `resetslot()` wipes them.

Losing these is silent — gestures keep half-working and start eating one another
— so `install.sh` warns if `~/.local/bin/lisgd` is missing or looks unpatched. It
checks for a string each patch adds; the cardinals one only reorders existing
code, so it cannot be detected that way and is not checked. lisgd itself is
still built by hand: `install.sh` does not clone or compile it.

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
| `$mod+Shift+m` | Mirror the screen to a Miracast TV (the Win+K equivalent) |
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
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±10% (silent - no desktop notification) |
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
| 2 fingers, in from right/left edge | Step one workspace by number, creating it |
| 2 fingers, up from bottom edge | Spotlight launcher |
| 2 fingers, down from top edge, 180px | Close the focused window |
| 1 finger near a window boundary (not on an edge) | Drag that boundary |

Windows also resize by dragging their (invisible) edges. See "Touchscreen
gestures" and "Touch-resizing windows and invisible borders" above.
