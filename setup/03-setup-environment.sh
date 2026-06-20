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

    # Re-run from the booted system (not redundant with 02): some VMs can't
    # write UEFI boot vars from within the chroot, so bootctl install in 02
    # leaves no boot entry. Running it here, post-boot, registers it properly.
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

    # claim the jack provider before anything pulls in jack2
    sudo pacman -S --needed --noconfirm pipewire-jack
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
        hyprland hyprpolkitagent hyprlock mako uwsm \
        thunar tumbler waybar rofi-wayland awww \
        ghostty fish foot grim slurp wl-clipboard \
        hypridle cliphist xdg-utils hyprsunset \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        noto-fonts noto-fonts-emoji
}

stow_dotfiles() {
    display_header "Stowing Dotfiles"
    # Pre-create ~/Pictures as a real dir so stow folds one level deeper:
    # only ~/Pictures/Wallpapers gets symlinked, leaving ~/Pictures itself
    # writable (e.g. for screenshots) instead of pointing into the repo.
    mkdir -p "$HOME/Pictures"

    local pkgs=(git fish hyprland ghostty waybar rofi wallpapers zed uwsm)
    for pkg in "${pkgs[@]}"; do
        stow -d "$HOME/dotfiles" -t "$HOME" "$pkg"
    done
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

    # Idempotency guard: the subvolume dance below (umount/rm /.snapshots,
    # create-config) is destructive and fails on a second run. Skip if the
    # root config already exists.
    if [[ -f /etc/snapper/configs/root ]]; then
        echo "Snapper root config already present, skipping."
        return 0
    fi

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

install_dotnet () {
    display_header "Installing .NET SDK (Microsoft direct)"

    command -v dotnet &>/dev/null && return 0   # skip if present
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel LTS --install-dir "$HOME/.dotnet"
    rm /tmp/dotnet-install.sh

    "$HOME/.dotnet/dotnet" tool install --global aspire.cli
}

install_rider () {
    display_header "Installing Rider"

    sudo pacman -S --noconfirm --needed flatpak

    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install --user -y flathub com.jetbrains.Rider
}

install_sddm() {
    display_header "Installing SDDM"
    sudo pacman -S --needed --noconfirm sddm
    sudo systemctl enable sddm.service
}

set_shell() {
    display_header "Setting fish as default shell"
    local fish_path
    fish_path=$(command -v fish)
    [[ -n "$fish_path" ]] || { echo "fish not found" >&2; return 1; }
    sudo usermod -s "$fish_path" "$USER"
}

# Main

require_home_dir
fix_bootctl

setup_pacman
install_tools

clone_dotfiles
stow_dotfiles

install_pipewire # install before desktop so pipeware-jack wins over jack2
install_desktop
install_sddm

set_shell

install_yay
install_steam
install_libreoffice
install_docker
install_dotnet
install_rider

# Do after all pacman work
install_snapper
