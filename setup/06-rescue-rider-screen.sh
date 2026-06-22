#!/bin/bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO (exit $?)" >&2' ERR
[[ $EUID -eq 0 ]] && { echo "Run as james, not root." >&2; exit 1; }

# 06-rescue-rider-screen.sh
# JetBrains Rider (class: jetbrains-rider) recurrently spawns off-screen at
# negative coords under Hyprland. This focuses it and centers it on its monitor.
#
# NOTE on the dispatch syntax: with the Lua config, `hyprctl dispatch <arg>` is
# evaluated as Lua (`return hl.dispatch(<arg>)`), so the classic
# `dispatch focuswindow address:0x...` form no longer works — we use the typed
# `hl.dsp.*` API instead.

display_header() {
    local msg="$1"
    local width bar
    width=$(tput cols 2>/dev/null || echo 80)

    # Build a bar of '#' exactly `width` wide
    bar=$(printf '#%.0s' $(seq "$width"))

    # Center the message: pad-left by (width - msglen) / 2
    local msglen=${#msg}
    local pad=$(( (width - msglen) / 2 ))
    (( pad < 0 )) && pad=0

    printf '%s\n' "$bar"
    printf '%*s%s\n' "$pad" '' "$msg"
    printf '%s\n' "$bar"
}

rescue_rider() {
    display_header "Rescuing Rider Window"

    command -v hyprctl >/dev/null || { echo "hyprctl not found — run this inside a Hyprland session." >&2; exit 1; }

    # Bail out gracefully if no Rider window is open
    if ! hyprctl clients 2>/dev/null | grep -q "class: jetbrains-rider"; then
        echo "No 'jetbrains-rider' window found — launch Rider first."
        return 0
    fi

    # Focus Rider by class, then center it on its current monitor
    hyprctl dispatch 'hl.dsp.focus({window="class:jetbrains-rider"})'
    hyprctl dispatch 'hl.dsp.window.center()'

    echo "Rider focused and centered."
}

rescue_rider
