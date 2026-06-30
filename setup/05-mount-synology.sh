#!/bin/bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO (exit $?)" >&2' ERR
[[ $EUID -eq 0 ]] && { echo "Run as james, not root (uses sudo per-command)." >&2; exit 1; }

# 05-mount-synology.sh
# Mounts the Synology NAS shares over CIFS. Finds the NAS by name on the LAN,
# writes a credentials file, and adds systemd-automount entries to fstab.

# Shares to mount: each is mounted at /mnt/<name> from //<nas-ip>/<name>.
SHARES=(volume0 volume1)

# Hostname to look for in the nmap sweep (matched case-insensitively).
NAS_NAME="Synology"

CREDENTIALS_FILE="/etc/samba/credentials/nas"

# Helper Functions

display_header() {
    local msg="$1"
    local width bar
    width=$(tput cols 2>/dev/null || echo 80)

    bar=$(printf '#%.0s' $(seq "$width"))

    local msglen=${#msg}
    local pad=$(( (width - msglen) / 2 ))
    (( pad < 0 )) && pad=0

    printf '%s\n' "$bar"
    printf '%*s%s\n' "$pad" '' "$msg"
    printf '%s\n' "$bar"
}

# Main Functions

install_packages() {
    display_header "Installing cifs-utils and nmap"
    sudo pacman -S --needed --noconfirm cifs-utils nmap
}

create_credentials() {
    display_header "Creating Samba credentials"

    if [[ -f "$CREDENTIALS_FILE" ]]; then
        echo "$CREDENTIALS_FILE already exists, leaving it."
        return 0
    fi

    local user pass
    read -rp "NAS username: " user
    read -rsp "NAS password: " pass
    echo

    sudo mkdir -p "$(dirname "$CREDENTIALS_FILE")"
    # Write via a root-owned tee so the password never lands in a world-readable
    # temp file; lock it down before it has any content races.
    printf 'username=%s\npassword=%s\n' "$user" "$pass" | sudo tee "$CREDENTIALS_FILE" >/dev/null
    sudo chmod 600 "$CREDENTIALS_FILE"
}

make_mount_dirs() {
    display_header "Creating mount directories"
    for share in "${SHARES[@]}"; do
        sudo mkdir -p "/mnt/$share"
    done
}

# Sweeps the local /24 with nmap and echoes the NAS IP. The sweep resolves
# reverse-DNS hostnames, so we match the line like:
#   Nmap scan report for Synology.lan (192.168.1.179)
find_nas_ip() {
    local iface cidr ip
    iface=$(ip route show default | awk '{print $5; exit}')
    cidr=$(ip -o -f inet addr show "$iface" | awk '{print $4; exit}')   # e.g. 192.168.1.42/24
    [[ -n "$cidr" ]] || { echo "Could not determine local subnet." >&2; return 1; }

    # nmap masks host bits, so passing the host CIDR scans the whole network.
    ip=$(sudo nmap -sn "$cidr" \
        | grep -iF "$NAS_NAME" \
        | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
        | head -1)

    [[ -n "$ip" ]] || { echo "Could not find '$NAS_NAME' on $cidr." >&2; return 1; }
    echo "$ip"
}

update_fstab() {
    local ip="$1"
    display_header "Updating /etc/fstab"

    local uid gid opts
    uid=$(id -u)
    gid=$(id -g)
    # mount-timeout caps how long an access blocks when the NAS is off (instead
    # of the long default CIFS timeout); idle-timeout unmounts after inactivity
    # so a stale handle to a powered-off NAS can't wedge file managers like Thunar.
    opts="_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=5,x-systemd.idle-timeout=60,credentials=$CREDENTIALS_FILE,uid=$uid,gid=$gid,file_mode=0664,dir_mode=0775,vers=3.1.1"

    # Manage our entries inside a marked block so re-runs replace rather than
    # duplicate. Strip any previous block first.
    sudo sed -i '/# >>> synology/,/# <<< synology/d' /etc/fstab

    {
        echo "# >>> synology"
        for share in "${SHARES[@]}"; do
            printf '//%s/%s  /mnt/%s  cifs  %s  0 0\n' "$ip" "$share" "$share" "$opts"
        done
        echo "# <<< synology"
    } | sudo tee -a /etc/fstab >/dev/null
}

pin_thunar_bookmarks() {
    display_header "Pinning shares to the Thunar sidebar"

    # Thunar (and the GTK file picker) read sidebar shortcuts from this file,
    # one "file://URI Label" per line. Drop any existing lines for our mounts,
    # then re-add them, so re-runs stay idempotent and other bookmarks survive.
    local file="$HOME/.config/gtk-3.0/bookmarks"
    mkdir -p "$(dirname "$file")"
    touch "$file"

    for share in "${SHARES[@]}"; do
        sed -i "\#^file:///mnt/$share\b#d" "$file"
        printf 'file:///mnt/%s %s\n' "$share" "${share^}" >> "$file"
    done
}

hide_thunar_desktop() {
    display_header "Hiding the Desktop sidebar entry"

    # Thunar shows XDG_DESKTOP_DIR as a sidebar item. Pointing it at $HOME (which
    # isn't a distinct dir) makes Thunar drop the entry. xdg-user-dirs-update
    # retains local edits to this file, so the change sticks across runs.
    local file="$HOME/.config/user-dirs.dirs"
    [[ -f "$file" ]] || { echo "$file not found, skipping."; return 0; }

    if grep -q '^XDG_DESKTOP_DIR=' "$file"; then
        sed -i 's|^XDG_DESKTOP_DIR=.*|XDG_DESKTOP_DIR="$HOME"|' "$file"
    else
        printf 'XDG_DESKTOP_DIR="$HOME"\n' >> "$file"
    fi

    # Clean up the orphaned dir, but only if it's empty.
    rmdir "$HOME/Desktop" 2>/dev/null || true
}

remount() {
    display_header "Remounting"
    sudo systemctl daemon-reload
    # With x-systemd.automount the mount triggers on first access; nofail means
    # a sleeping NAS won't wedge boot, so don't treat a miss here as fatal.
    for share in "${SHARES[@]}"; do
        sudo mount "/mnt/$share" || true
    done
}

# Main

install_packages
create_credentials
make_mount_dirs

display_header "Sweeping LAN for $NAS_NAME"
nas_ip=$(find_nas_ip)
echo "Found $NAS_NAME at $nas_ip"

update_fstab "$nas_ip"
remount
pin_thunar_bookmarks
hide_thunar_desktop

echo "Done. Shares mounted under /mnt/{$(IFS=,; echo "${SHARES[*]}")}."
