#!/bin/sh
# Brightness keys with a screen-off step below the lowest brightness.
#   brightness.sh down   5% down; at the minimum, turns the display off
#   brightness.sh up     turns the display back on if it is off, else 5% up
# amdgpu_bl0 still lights the panel at its minimum, so "off" is sway's output
# power off. Everything keeps running (farm, music); only the panel goes dark.

off() { swaymsg -t get_outputs -r | jq -e 'any(.[]; .power == false)' >/dev/null; }

case "$1" in
    down)
        if [ "$(brightnessctl get)" -le 1 ]; then
            swaymsg 'output * power off' >/dev/null
        else
            brightnessctl -q set 5%-
        fi
        ;;
    up)
        if off; then
            swaymsg 'output * power on' >/dev/null
        else
            brightnessctl -q set 5%+
        fi
        ;;
esac
