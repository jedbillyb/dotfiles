#!/bin/bash
# waybar custom module for open pull requests waiting on you. Emits one JSON
# object.
#
#   "custom/pr": {
#       "exec": "~/.config/waybar/pr-status.sh",
#       "return-type": "json",
#       "interval": 120,
#       "signal": 8,
#       "on-click": "~/.config/waybar/pr-status.sh click"
#   }
#
# All the work is in scripts/gh-prs; this is the waybar shim, the same split as
# heatpump-status.py and the vpn module. Resolved through the symlink rather
# than through PATH, because waybar is started by sway and does not necessarily
# have ~/.local/bin on it.
set -u

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
GH_PRS="$HERE/../scripts/gh-prs"

if [ "${1:-}" = "click" ]; then
  # Open the same set on github.com. The tooltip already says what is waiting,
  # so the click is for going and doing something about it. The refresh runs
  # first and detached: by the time you come back from reviewing, the bar
  # should not still be claiming the PR is open.
  "$GH_PRS" --web
  setsid nohup "$GH_PRS" --refresh --count >/dev/null 2>&1 &
  # waybar redraws the module on this signal, so the count updates without
  # waiting out the poll interval.
  ( sleep 8; pkill -RTMIN+8 waybar ) >/dev/null 2>&1 &
  exit 0
fi

# A missing or broken gh-prs must still produce valid JSON. Anything else and
# waybar drops the whole bar's parse, not just this module.
if [ ! -x "$GH_PRS" ]; then
  printf '{"text":"pr ?","class":"error","tooltip":"gh-prs not found"}\n'
  exit 0
fi

OUT=$("$GH_PRS" --waybar 2>/dev/null)
case "$OUT" in
  \{*\}) printf '%s\n' "$OUT" ;;
  *)     printf '{"text":"pr ?","class":"error","tooltip":"gh-prs failed"}\n' ;;
esac
