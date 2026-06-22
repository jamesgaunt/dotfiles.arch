#!/bin/bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO (exit $?)" >&2' ERR
[[ $EUID -eq 0 ]] && { echo "Run as james, not root (uses sudo per-command)." >&2; exit 1; }

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

generate_ssh_key() {
    display_header "Generating SSH Key"

    local key="$HOME/.ssh/id_ed25519"
    [[ -f "$key" ]] && return 0   # already exists, don't clobber
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "james.gaunt@webfuel.com" -f "$key" -N ""

    echo "Add this public key to GitHub (Settings → SSH and GPG keys):"
    cat "$key.pub"
    echo "Then repoint dotfiles: git -C \"\$HOME/dotfiles\" remote set-url origin git@github.com:jamesgaunt/dotfiles.arch.git"
}

# Outputs a key to authenticate with github
generate_ssh_key

# git -C "$HOME/dotfiles" remote set-url origin git@github.com:jamesgaunt/dotfiles.arch.git
