#!/usr/bin/env bash
# Switch every monitor to its workspace within "group" N, simultaneously.
#
# Workspaces are pinned to monitors in hyprland.lua so that
#   workspace = (group - 1) * <num monitors> + <monitor index> + 1
# i.e. group 1 = {1,2,3,4}, group 2 = {5,6,7,8}, group 3 = {9,10,11,12}, ...
# one workspace on each monitor. This makes one keypress page all monitors
# to the same group at once.
#
# Usage: workspace-group.sh <group-number>
set -euo pipefail

group="$1"

# Monitor order defines the index used in the pinning formula above.
# Only the bottom monitors are paged; the top widescreen is independent.
# Keep this in sync with bottomMonitors in hyprland.lua.
mons=(DP-1 DP-2 DP-3)
nmon=${#mons[@]}

# Remember the focused monitor so focus stays put after we page everything.
focused=$(hyprctl monitors | awk '/^Monitor /{m=$2} /focused: yes/{print m; exit}')

# This Hyprland uses Lua dispatchers: `hyprctl dispatch` wraps its argument in
# hl.dispatch(...), so we pass hl.dsp.* expressions rather than bare keywords.
for i in "${!mons[@]}"; do
    ws=$(( (group - 1) * nmon + i + 1 ))
    hyprctl dispatch "hl.dsp.focus({ workspace = $ws })"
done

hyprctl dispatch "hl.dsp.focus({ monitor = \"${focused:-${mons[0]}}\" })"
