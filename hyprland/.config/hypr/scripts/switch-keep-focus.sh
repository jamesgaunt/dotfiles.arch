#!/usr/bin/env bash
# Switch to a workspace (focusing its monitor) but return keyboard focus to the
# monitor you were on. Used to flip the top widescreen monitor's workspace
# without pulling focus away from the bottom monitors you're working on.
#
# Usage: switch-keep-focus.sh <workspace>
set -euo pipefail

ws="$1"

focused=$(hyprctl monitors | awk '/^Monitor /{m=$2} /focused: yes/{print m; exit}')

# This Hyprland uses Lua dispatchers (hyprctl dispatch wraps its arg in
# hl.dispatch(...)), so pass hl.dsp.* expressions rather than bare keywords.
hyprctl dispatch "hl.dsp.focus({ workspace = $ws })"
[[ -n "$focused" ]] && hyprctl dispatch "hl.dsp.focus({ monitor = \"$focused\" })"
