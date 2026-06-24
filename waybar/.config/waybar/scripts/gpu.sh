#!/usr/bin/env bash
# GPU utilization + temperature for waybar (NVIDIA)
read -r util temp < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu \
    --format=csv,noheader,nounits | awk -F', ' '{print $1, $2}')
printf '%s%% %s°C\n' "$util" "$temp"
