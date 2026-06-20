#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] && { echo "Run as james, not root (uses sudo per-command)." >&2; exit 1; }

# 03-setup-environment.sh
# Sets up the environment after installation.

# Helper Functions

require_home_dir() {
    [[ "$PWD" == "$HOME" ]] || {
        echo "Run this from your home directory ($HOME). You're in: $PWD" >&2
        exit 1
    }
}

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

# Main Functions

fix_bootctl() {
    display_header "Fixing bootctl so it works with systemd-boot"

    sudo bootctl install
}

setup_pacman() {
    display_header "Setting up Pacman"

    # enable pacman multilib (needed later for steam)
    sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf

    # sync databases now that multilib is enabled, before any install
    sudo pacman -Syu --noconfirm

    # setup mirrors
    sudo pacman -S --needed --noconfirm reflector
    sudo reflector --country "United Kingdom" --age 12 --protocol https \
        --sort rate --save /etc/pacman.d/mirrorlist

    # refresh against the new mirrorlist
    sudo pacman -Syu --noconfirm
}

install_tools() {
    display_header "Installing Tools"

    sudo pacman -S --needed --noconfirm \
        git zed chromium firefox stow ttf-jetbrains-mono-nerd \
        zoxide
}

clone_dotfiles() {
    local repo="https://github.com/jamesgaunt/dotfiles.arch.git"
    local dest="$HOME/dotfiles"

    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" pull --ff-only
    else
        git clone "$repo" "$dest"
    fi
}

install_desktop() {
    display_header "Installing Desktop Environment"

    sudo pacman -S --needed --noconfirm \
        hyprland hyprpolkitagent uwsm \
        thunar tumbler waybar rofi-wayland awww \
        ghostty fish foot

    stow -d "$HOME/dotfiles" -t "$HOME" hyprland
    stow -d "$HOME/dotfiles" -t "$HOME" ghostty
    stow -d "$HOME/dotfiles" -t "$HOME" fish
    stow -d "$HOME/dotfiles" -t "$HOME" waybar
    stow -d "$HOME/dotfiles" -t "$HOME" rofi
}

install_pipewire () {
    display_header "Installing Pipewire"

    sudo pacman -S --needed --noconfirm \
        pipewire pipewire-alsa pipewire-jack pipewire-pulse \
        wireplumber \
        pipewire-audio

    systemctl --user enable pipewire pipewire-pulse wireplumber
}

install_snapper() {
    display_header "Installing Snapper"

    sudo pacman -S --needed --noconfirm \
        snapper snap-pac

    # snapper will create its own .snapshots subvolume
    # unmount ours and remove the existing directory
    sudo umount /.snapshots
    sudo rm -r /.snapshots

    # create snapper config for root
    sudo snapper -c root create-config /

    # delete snapper's auto-created subvolume and restore ours
    sudo btrfs subvolume delete /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a

    # fix permissions
    sudo chmod 750 /.snapshots

    # Turn off timeline creation
    sudo sed -i 's/TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/root

    # Enable and start snapper-cleanup timer
    sudo systemctl enable --now snapper-cleanup.timer
}

install_yay() {
    display_header "Installing Yay"
    command -v yay &>/dev/null && return 0   # already installed, skip
    sudo pacman -S --needed --noconfirm git base-devel
    local tmp; tmp=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm)
    rm -rf "$tmp"
}

install_steam() {
    display_header "Installing Steam"

    sudo pacman -S --noconfirm --needed steam gamescope \
        lib32-nvidia-utils lib32-vulkan-icd-loader
}

install_libreoffice() {
    display_header "Installing Libreoffice"

    sudo pacman -S --noconfirm --needed libreoffice-still
}

install_docker () {
    display_header "Installing Docker"

    sudo pacman -S --noconfirm --needed docker docker-compose
    sudo systemctl enable --now docker.service

    # assign user to docker group (restart required)
    sudo usermod -aG docker "$USER"
}

# Main

require_home_dir
fix_bootctl
setup_pacman
install_tools
clone_dotfiles
install_desktop
install_pipewire
install_yay
install_steam
install_libreoffice
install_docker

# Do Last
install_snapper
