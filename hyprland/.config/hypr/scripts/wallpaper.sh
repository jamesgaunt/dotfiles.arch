#!/usr/bin/env bash

INTERVAL=300 # In seconds
WALL_DIR="$HOME/Pictures/Wallpapers"

sleep 10
while true; do
    WALL=$(find -L "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n 1)
    awww img "$WALL" --transition-fps 30 --transition-step 2
    sleep "$INTERVAL"
done
