#!/bin/bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

# 01-prepare-disk.sh
# Sets up the disk for installation by selecting a disk and partitioning it.

# Helper Functions

require_home_dir() {
    [[ "$PWD" == "$HOME" ]] || {
        echo "Run this from your home directory ($HOME). You're in: $PWD" >&2
        exit 1
    }
}

confirm() {
    read -rp "${1:-Are you sure?} [Y/n] " reply
    case "$reply" in
        ''|[Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
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

enumerate_disks_by_id() {
    local d target type
    declare -A seen
    for d in /dev/disk/by-id/*; do
        [[ "$d" == *-part* ]] && continue           # skip partitions
        target=$(readlink -f "$d")
        [[ -n "${seen[$target]:-}" ]] && continue   # skip dupes
        # keep only whole disks — drops rom (DVD), loop, etc.
        type=$(lsblk -dno TYPE "$target" 2>/dev/null)
        [[ "$type" == "disk" ]] || continue
        seen["$target"]=1
        printf '%s\n' "$d"
    done
}

select_disk() {
    display_header "Select Disk: WARNING this will destroy all data on the selected disk"

    local disks=()
    mapfile -t disks < <(enumerate_disks_by_id)
    (( ${#disks[@]} )) || { echo "No disks found." >&2; return 1; }

    lsblk -dno NAME,SIZE,MODEL
    echo

    local choice COLUMNS=1                 # force single-column menu
    local PS3="Select the disk to install to (number, or 1 to abort): "
    select choice in "Abort" "${disks[@]}"; do
        if [[ "$choice" == "Abort" ]]; then
            echo "Aborted." >&2
            return 1
        fi
        [[ -n "$choice" ]] && break
        echo "Invalid selection, try again." >&2
    done

    [[ -n "${choice:-}" ]] || { echo "No disk selected." >&2; return 1; }
    DISK="$choice"
    echo "Selected disk: $DISK"
}

# Main Functions

prepare_mountpoint() {
    # Clean up any leftover mounts from a previous run so we can retry safely
    swapoff -a 2>/dev/null || true
    local mp
    while read -r mp; do
        umount -R "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null || true
    done < <(findmnt -rno TARGET | grep -E '^/mnt(/|$)' | sort -r)
    udevadm settle
}

partition_disk() {
    display_header "Partitioning Disk: $DISK"

    sfdisk --wipe always "$DISK" <<EOF
label: gpt
size=1GiB, type=U, name=ESP
type=L, name=root
EOF
  udevadm settle
}

format_partitions() {
    display_header "Formatting Partitions"

    mkfs.fat -F32 -n ESP   "${DISK}-part1"
    mkfs.btrfs -f -L root  "${DISK}-part2"
}

create_btrfs_subvolumes() {
    display_header "Creating BTRFS Subvolumes"

    mount "${DISK}-part2" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@var_cache
    btrfs subvolume create /mnt/@var_lib_docker
    umount /mnt
}

mount_btrfs_subvolumes() {
    display_header "Mounting BTRFS Subvolumes"

    local opts="noatime,compress=zstd:1,discard=async,space_cache=v2"

    mount -o "$opts",subvol=@ "${DISK}-part2" /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,var/cache,var/lib/docker}

    mount -o $opts,subvol=@home             "${DISK}-part2"    /mnt/home
    mount -o $opts,subvol=@snapshots        "${DISK}-part2"    /mnt/.snapshots
    mount -o $opts,subvol=@var_log          "${DISK}-part2"    /mnt/var/log
    mount -o $opts,subvol=@var_cache        "${DISK}-part2"    /mnt/var/cache
    mount -o $opts,subvol=@var_lib_docker   "${DISK}-part2"    /mnt/var/lib/docker
}

mount_efi_partition() {
    display_header "Mounting EFI Partition"

    mkdir -p /mnt/efi
    mount "${DISK}-part1" /mnt/efi
}

install_base() {
    display_header "Installing Base System: Layer 1"
    pacstrap -K /mnt base linux linux-firmware btrfs-progs curl
}

generate_fstab() {
    display_header "Generating fstab"

    genfstab -U /mnt >> /mnt/etc/fstab
}

# Main

display_header "01-prepare-disk.sh:"

require_home_dir
select_disk || exit 0
prepare_mountpoint
partition_disk
format_partitions

create_btrfs_subvolumes
mount_btrfs_subvolumes
mount_efi_partition

install_base
generate_fstab

display_header "Disk Preparation Complete"
