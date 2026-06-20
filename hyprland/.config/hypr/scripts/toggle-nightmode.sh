#!/bin/bash
# toggle-nightmode.sh
state_file="/tmp/nightmode_state"
if [[ -f "$state_file" ]]; then
    hyprctl hyprsunset temperature 6500
    rm "$state_file"
else
    hyprctl hyprsunset temperature 4000
    touch "$state_file"
fi
