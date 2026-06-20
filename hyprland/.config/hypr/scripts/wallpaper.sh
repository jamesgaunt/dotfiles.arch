#!/usr/bin/env bash

DEFAULT_INTERVAL=300 # In seconds
WALL_DIR="$HOME/Pictures/Wallpapers"

while true; do
    WALL=$(find "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n 1)
    awww img "$WALL" --transition-fps 30 --transition-step 2
    sleep "${2:-$DEFAULT_INTERVAL}"
done
