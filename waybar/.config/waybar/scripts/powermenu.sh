#!/bin/bash
chosen=$(printf "Shutdown\nReboot\nLock\nSuspend\nLogout" | \
    rofi -dmenu -i -p "Power")

case "$chosen" in
    *Shutdown) systemctl poweroff ;;
    *Reboot)   systemctl reboot ;;
    *Lock)     hyprlock ;;          # or your lock command
    *Suspend)  systemctl suspend ;;
    *Logout)   hyprctl dispatch exit ;;
esac
