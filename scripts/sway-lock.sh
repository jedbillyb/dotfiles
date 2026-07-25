#!/bin/sh
# Lock the screen with an animated blur.
#
# Takes a screenshot, derives a few progressively blurrier copies of it, and
# hands them to swaylock-fprintd, which cross-fades through them on lock and
# back out again on a successful unlock.
#
# waybar stays visible on top of the lock surface; that is handled by the
# compositor (see `lock_visible_namespace waybar` in the sway config), not
# here. The blurred screenshot deliberately includes the bar area, so the real
# waybar lines up over it.

set -eu

LOCKER="$HOME/.local/bin/swaylock-fprintd"
# The locker eases this curve in and out, so the perceived motion is slower at
# both ends than the raw number suggests -- 300ms felt like a snap.
DURATION=700

# Indicator theming, matched to waybar/style.css: #242424 at 0.85 alpha (d9)
# background, #cccccc text, #666666 dim, #ffffff focus. Deliberately
# monochrome -- swaylock's stock green/blue states clash badly with it.
# The line between inside and ring is transparent, which is what removes the
# hard black circle outline; the translucent inside lets the blur show through.
THEME="
--indicator-radius 90
--indicator-thickness 5
--inside-color 242424d9
--ring-color 666666ff
--line-color 00000000
--separator-color 00000000
--text-color ccccccff
--key-hl-color ffffffff
--bs-hl-color 888888ff
--inside-ver-color 242424d9
--ring-ver-color ccccccff
--line-ver-color 00000000
--text-ver-color ffffffff
--inside-clear-color 242424d9
--ring-clear-color 888888ff
--line-clear-color 00000000
--text-clear-color ccccccff
--inside-wrong-color 2b1e1ed9
--ring-wrong-color a05a5aff
--line-wrong-color 00000000
--text-wrong-color d09090ff
--inside-caps-lock-color 242424d9
--ring-caps-lock-color 998866ff
--line-caps-lock-color 00000000
--text-caps-lock-color ddccaaff
--caps-lock-key-hl-color ffffffff
--caps-lock-bs-hl-color 888888ff
--layout-bg-color 242424d9
--layout-border-color 00000000
--layout-text-color ccccccff
"

# swayidle and the keybind can both fire; only ever run one locker.
LOCKFILE=/tmp/sway-lock.$(id -u).lock
exec 9>"$LOCKFILE"
if ! flock -n 9; then
	exit 0
fi

# The frames are screenshots of the unlocked desktop, so keep them in tmpfs
# and private to this user.
FRAMES=$(mktemp -d /dev/shm/swaylock-blur.XXXXXX)
chmod 700 "$FRAMES"
cleanup() {
	rm -rf "$FRAMES"
}
trap cleanup EXIT INT TERM

# frame-00 is the sharp desktop at full resolution. The rest are generated at
# quarter scale (blurred content upscales without visible loss, and it keeps
# both the ImageMagick pass and swaylock's memory use small). Each -write
# compounds the previous blur, giving a progressive ramp in one invocation.
# grim -l 0 disables PNG compression: 30ms instead of 670ms, and the file only
# has to survive a few hundred ms in tmpfs. This delay is time the screen is
# still unlocked, so it is worth keeping short.
blurred=false
if grim -l 0 "$FRAMES/frame-00.png" 2>/dev/null; then
	if magick "$FRAMES/frame-00.png" -resize 25% \
		-blur 0x3 -write "$FRAMES/frame-01.png" \
		-blur 0x3 -write "$FRAMES/frame-02.png" \
		-blur 0x4 -write "$FRAMES/frame-03.png" \
		-blur 0x5 "$FRAMES/frame-04.png" 2>/dev/null; then
		blurred=true
	fi
fi

# Fall back to a plain black lock if grim or ImageMagick failed, so a broken
# screenshot can never leave the machine unlocked.
# $THEME is deliberately unquoted: it must word-split into separate flags.
if [ "$blurred" = true ]; then
	# shellcheck disable=SC2086
	# -c is a safety net: without it swaylock's background defaults to white,
	# which flashes if anything is ever painted before a blur frame.
	"$LOCKER" --fingerprint -s fill -c 1a1a1a \
		--blur-frames "$FRAMES" --blur-duration "$DURATION" $THEME "$@"
else
	# shellcheck disable=SC2086
	"$LOCKER" --fingerprint -c 1a1a1a $THEME "$@"
fi
