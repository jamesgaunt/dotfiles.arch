#!/usr/bin/env bash
# Move the active window to the current monitor's slot in "group" N, without
# switching the view. Pairs with workspace-group.sh: a window on DP-2 sent to
# group 3 lands on DP-2's group-3 workspace.
#
# Usage: move-to-group.sh <group-number>
set -euo pipefail

group="$1"

# Keep this monitor order in sync with workspace-group.sh / hyprland.lua.
# Only the bottom monitors are paged into groups. If the active window is on the
# top monitor, idx stays 0 and it drops to DP-1's slot in the group.
mons=(DP-1 DP-2 DP-3)
nmon=${#mons[@]}

# The active window is on the focused monitor.
focused=$(hyprctl monitors | awk '/^Monitor /{m=$2} /focused: yes/{print m; exit}')

idx=0
for i in "${!mons[@]}"; do
    if [[ "${mons[$i]}" == "$focused" ]]; then
        idx=$i
        break
    fi
done

ws=$(( (group - 1) * nmon + idx + 1 ))
# silent = move without following (this Hyprland uses Lua dispatchers).
hyprctl dispatch "hl.dsp.window.move({ workspace = $ws, silent = true })"
