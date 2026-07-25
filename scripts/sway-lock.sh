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
DURATION=300

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
if [ "$blurred" = true ]; then
	"$LOCKER" --fingerprint -s fill \
		--blur-frames "$FRAMES" --blur-duration "$DURATION" "$@"
else
	"$LOCKER" --fingerprint -c 000000 "$@"
fi
