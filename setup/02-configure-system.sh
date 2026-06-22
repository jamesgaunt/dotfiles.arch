#!/bin/bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO (exit $?)" >&2' ERR
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

# 02-configure-system.sh
# Configures the system after installation.

# Helper Functions

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

install_base() {
    display_header "Installing Base System: Layer 2"
    pacman -Syu --noconfirm
    pacman -S --noconfirm base-devel linux-headers dosfstools efibootmgr \
        intel-ucode nano networkmanager sudo openssh
}

install_gpu() {
    display_header "Installing GPU Drivers"
    pacman -S --noconfirm nvidia-open-dkms nvidia-utils vulkan-icd-loader egl-wayland
    dkms status | grep -q "nvidia.*installed" || {
            echo "NVIDIA DKMS module failed to build" >&2; exit 1
        }
}

configure_mkinitcpio() {
    sed -i \
        -e 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        -e 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block filesystems fsck)/' \
        /etc/mkinitcpio.conf
    grep -q '^MODULES=(nvidia ' /etc/mkinitcpio.conf || {
        echo "Failed to set NVIDIA MODULES" >&2; exit 1
    }
    grep -q '^HOOKS=(base systemd' /etc/mkinitcpio.conf || {
        echo "Failed to set HOOKS" >&2; exit 1
    }
}

configure_nvidia_options() {
    cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
}

blacklist_nouveau() {
    echo "blacklist nouveau" > /etc/modprobe.d/nouveau-blacklist.conf
}

emit_cmdline() {
    local ROOT_UUID
    ROOT_UUID=$(findmnt -no UUID /)
    [[ -n "$ROOT_UUID" ]] || { echo "Could not determine root UUID" >&2; exit 1; }
    echo "root=UUID=${ROOT_UUID} rootflags=subvol=@ rw nvidia-drm.modeset=1" \
        > /etc/kernel/cmdline
    cat /etc/kernel/cmdline
}

configure_uki_preset() {
    cat > /etc/mkinitcpio.d/linux.preset <<'EOF'
# mkinitcpio preset file for the 'linux' package — UKI output

ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/Linux/arch-linux.efi"

fallback_options="-S autodetect"
fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
EOF

    mkdir -p /efi/EFI/Linux
}

build_uki() {
    display_header "Building UKI"
    mkinitcpio -P
    # Verify the UKI actually landed on the ESP — this is the make-or-break check
    [[ -s /efi/EFI/Linux/arch-linux.efi ]] || {
        echo "UKI was not generated at /efi/EFI/Linux/arch-linux.efi" >&2
        exit 1
    }
    ls -lh /efi/EFI/Linux/
}

install_bootloader() {
    display_header "Installing Bootloader"
    bootctl install
    # Verify the EFI binary and a boot entry were created
    [[ -s /efi/EFI/systemd/systemd-bootx64.efi ]] || {
        echo "systemd-boot binary not found after bootctl install" >&2
        exit 1
    }
}

configure_loader() {
    cat > /efi/loader/loader.conf <<'EOF'
default  arch-linux.efi
timeout  3
console-mode max
editor   no
EOF
}

configure_locale_time() {
    display_header "Configuring Locale and Time"
    ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
    hwclock --systohc
    echo "en_GB.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_GB.UTF-8" > /etc/locale.conf
    echo "KEYMAP=uk" > /etc/vconsole.conf
    echo "thebeast" > /etc/hostname
}

enable_services() {
    display_header "Enabling Services"
    systemctl enable NetworkManager
    systemctl enable sshd
    systemctl enable systemd-timesyncd   # NTP clock sync (ships with systemd)
    systemctl enable nvidia-suspend.service nvidia-resume.service
}

configure_zram() {
    display_header "Configuring zram swap"
    pacman -S --noconfirm zram-generator
    cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 4, 8192)
compression-algorithm = zstd
EOF
}

configure_user() {
    display_header "Configuring User"
    # Configure sudo for the wheel group (idempotent: overwrites the drop-in)
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
    chmod 0440 /etc/sudoers.d/10-wheel

    # Soften faillock so a transient input hiccup (e.g. dead keyboard for ~20s
    # after an NVIDIA/Hyprland resume) can't trigger the default 10-min lockout
    # (deny=3 / unlock_time=600). Idempotent.
    grep -q '^deny = 10' /etc/security/faillock.conf || cat >> /etc/security/faillock.conf <<'EOF'

# Softened: avoid lockout from a transient input hiccup
deny = 10
unlock_time = 60
EOF

    # Create the user with wheel membership (only if not already present)
    if ! id -u james &>/dev/null; then
        useradd -m -G wheel -s /bin/bash james
    fi

    # Set the password interactively — script pauses here for you to type it
    echo "Set password for user 'james':"
    passwd james

    # root stays locked (Arch default) — no action needed
}

# Main

install_base
install_gpu
configure_mkinitcpio
configure_nvidia_options
blacklist_nouveau
configure_locale_time
emit_cmdline
configure_uki_preset
build_uki
install_bootloader
configure_loader
configure_user
configure_zram
enable_services

display_header "System Configuration Complete"
