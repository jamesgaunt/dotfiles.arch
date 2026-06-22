#!/bin/bash
chosen=$(printf "Shutdown\nReboot\nLock\nLogout" | \
    rofi -dmenu -i -p "Power")

case "$chosen" in
    *Shutdown) systemctl poweroff ;;
    *Reboot)   systemctl reboot ;;
    *Lock)     hyprlock ;;          # or your lock command
    *Logout)   uwsm stop ;;          # uwsm-managed session: tear down cleanly (not `hyprctl dispatch exit`)
esac
