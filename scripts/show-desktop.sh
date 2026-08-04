#!/bin/sh
# Toggle "show desktop": jump to an empty workspace so the bare wallpaper is
# visible, and jump straight back on the second press.
#
# An earlier version stashed each window in the scratchpad. Don't do that:
# entering the scratchpad makes a window floating and resizes it, which is the
# size-pop you see on the way back, and lifting windows out of the tree throws
# away the split layout, so they never land in the same spots again. Switching
# workspaces leaves the tree completely untouched.

# Single character, so waybar shows it as "D" alongside the numbered
# workspaces instead of a wide label that shoves the clock off centre.
desktop_ws="D"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/sway-show-desktop"
mkdir -p "$state_dir"

# One state file per output, so each monitor toggles independently.
output=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .output')
ws=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
[ -n "$ws" ] || exit 0

state="$state_dir/$(printf '%s' "$output" | tr -c 'A-Za-z0-9._-' '_')"

if [ "$ws" = "$desktop_ws" ] && [ -s "$state" ]; then
    read -r previous < "$state"
    rm -f "$state"
    [ -n "$previous" ] && swaymsg "workspace --no-auto-back-and-forth \"$previous\"" >/dev/null
    exit 0
fi

# Stale state (the workspace was left some other way) is simply overwritten.
printf '%s\n' "$ws" > "$state"
swaymsg "workspace --no-auto-back-and-forth \"$desktop_ws\"" >/dev/null
