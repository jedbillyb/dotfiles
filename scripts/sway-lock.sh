#!/bin/sh
# Lock the screen with an animated blur.
#
# Takes a screenshot, derives a few progressively blurrier copies of it, and
# hands them to swaylock-fprintd, which cross-fades through them on lock and
# back out again on a successful unlock.
#
# waybar stays visible on top of the lock surface; that is handled by the
# compositor (see `lock_visible_namespace waybar` in the sway config), not
# here. The bar strip is flattened out of the blur frames -- see BAR_HEIGHT.

set -eu

LOCKER="$HOME/.local/bin/swaylock-fprintd"
# The locker eases this curve in and out, so the perceived motion is slower at
# both ends than the raw number suggests -- 300ms felt like a snap.
DURATION=700

# Height of the waybar strip in physical pixels: the "height" in waybar/config
# times the output scale (both 16 and 1 here).
#
# waybar's background is rgba(36,36,36,0.85), i.e. 15% transparent, and the
# screenshot captures the whole desktop including the bar. Left alone, the live
# bar sits over a blurred copy of itself and the two smear against each other
# as the blur ramps -- jagged doubled text. So the bar's pixels have to go.
#
# They are replaced by mirroring the desktop from just below the bar upward,
# rather than by a flat fill. A flat fill also kills the ghost, but it makes
# the strip pop from flat colour to real wallpaper the instant the lock
# releases, which is visible at the end of every unlock. Mirrored content
# blurs along with the rest of the image and hands back over unnoticed.
BAR_HEIGHT=16

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
if grim -l 0 "$FRAMES/raw.png" 2>/dev/null; then
	# The bar strip is replaced before frame-00 is written, so the sharp frame
	# is covered too -- the unlock animation lands on frame-00, so leaving it
	# out would bring the artifact back at the tail of every unlock. Because
	# the replacement is ordinary desktop content it blurs correctly along with
	# everything else, and needs no touching up between blurs.
	#
	# compression-level=0 matters as much here as grim's -l 0 does: magick
	# writes the full-resolution frame-00, and at default compression that one
	# write alone costs ~670ms. -strip drops metadata, and Point sampling is
	# the cheapest resize -- no point interpolating carefully when every frame
	# that uses it is about to be blurred. Together: ~280ms.
	if magick "$FRAMES/raw.png" \
		-define png:compression-level=0 -strip \
		\( +clone -crop "x${BAR_HEIGHT}+0+${BAR_HEIGHT}" +repage -flip \) \
		-geometry +0+0 -composite \
		-write "$FRAMES/frame-00.png" \
		-filter Point -resize 25% \
		-blur 0x3 -write "$FRAMES/frame-01.png" \
		-blur 0x3 -write "$FRAMES/frame-02.png" \
		-blur 0x4 -write "$FRAMES/frame-03.png" \
		-blur 0x5 "$FRAMES/frame-04.png" 2>/dev/null; then
		blurred=true
	fi
	# Not one of the frames, and it is the one copy still holding an
	# un-flattened image of the desktop.
	rm -f "$FRAMES/raw.png"
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
