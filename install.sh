#!/bin/bash
set -Eeuo pipefail

# Validate dependencies
check_dependency() {
  command -v "$1" >/dev/null 2>&1 || { echo >&2 "$1 is required but not installed. Aborting."; exit 1; }
}

validate_dependencies() {
  check_dependency timedatectl
  check_dependency dialog
  check_dependency lsblk
  check_dependency parted
  check_dependency wipefs
}

# Colors
NOFORMAT='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'

# Trap function for cleanup and error handling
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # Script cleanup here
  # Add any additional cleanup steps if necessary
}

trap cleanup SIGINT SIGTERM ERR EXIT

# Function to print messages with color
msg() {
  echo >&2 -e "${1-}"
}

# Introduction
msg "${BLUE}Welcome to Arch Linux Installer!${NOFORMAT}"
msg

# 1. Prepare environment

# 1.1. Validate dependencies
validate_dependencies

# 1.2. Update system clock
timedatectl set-ntp true

# 1.3. Print warning
msg "${YELLOW}WARNING: This script will remove all existing data on the disk${NOFORMAT}"
msg "${YELLOW}WARNING: This script is experimental and is not verified${NOFORMAT}"
msg "${YELLOW}WARNING: This script is not intended for use in production${NOFORMAT}"
msg

# 2. User credentials

# 2.1. Hostname
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
[[ -n "$hostname" ]] || { echo "Hostname cannot be empty"; exit 1; }

# 2.2. Root password
root_password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
[[ -n "$root_password" ]] || { echo "Admin password cannot be empty"; exit 1; }
root_password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
[[ "$root_password" == "$root_password2" ]] || { echo "Passwords do not match"; exit 1; }

# 2.3. Username
username=$(dialog --stdout --inputbox "Enter username" 0 0) || exit 1
[[ -n "$username" ]] || { echo "Username cannot be empty"; exit 1; }

# 2.4. User password
user_password=$(dialog --stdout --passwordbox "Enter user password" 0 0) || exit 1
[[ -n "$user_password" ]] || { echo "User password cannot be empty"; exit 1; }
user_password2=$(dialog --stdout --passwordbox "Enter user password again" 0 0) || exit 1
[[ "$user_password" == "$user_password2" ]] || { echo "Passwords do not match"; exit 1; }

# 2.5. Timezone
msg "${BLUE}Available timezones:${NOFORMAT}"
timezones=$(timedatectl list-timezones)
timezone=$(dialog --stdout --menu "Select timezone" 0 0 0 $timezones) || exit 1

# 2.6. Locale
msg "${BLUE}Available locales:${NOFORMAT}"
locales=$(cat /etc/locale.gen | grep -v "#")
locale=$(dialog --stdout --menu "Select locale" 0 0 0 $locales) || exit 1

# 2.7. Keymap
msg "${BLUE}Available keymaps:${NOFORMAT}"
keymaps=$(ls /usr/share/kbd/keymaps/**/*.map.gz | grep -v "iso")
keymap=$(dialog --stdout --menu "Select keymap" 0 0 0 $keymaps) || exit 1

# 3. Disk partitioning

# 3.1. Disk name
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 $devicelist) || exit 1
[[ -n "$device" ]] || { echo "No disk selected. Aborted."; exit 1; }
clear

# 3.2. Partition the disks
parted --script "$device" -- mklabel gpt \
  mkpart ESP fat32 1Mib 512MiB \
  set 1 boot on \
  mkpart primary linux-swap 512MiB 4GiB \
  mkpart primary ext4 4GiB 100%

# 3.3. Format the partitions
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "$part_boot"
wipefs "$part_swap"
wipefs "$part_root"

mkfs.vfat -F32 "$part_boot"
mkswap "$part_swap"
mkfs.ext4 "$part_root"

# 3.4. Mount the file systems
swapon "$part_swap"
mount "$part_root" /mnt
mkdir /mnt/boot
mount "$part_boot" /mnt/boot

# 4. Install the base packages

# 4.1. Reload the mirror list
reflector --latest 200 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# 4.2. Enable parallel downloads
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 5/" /etc/pacman.conf

# 4.3. Install base packages
pacstrap /mnt base base-devel linux linux-firmware nano networkmanager efibootmgr grub os-prober intel-ucode sudo git neofetch

# 4.4. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 5. Chroot

# 5.1. Time zone
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
arch-chroot /mnt hwclock --systohc

# 5.2. Localization
arch-chroot /mnt sed -i "s/#$locale/$locale/" /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=$locale" > /etc/locale.conf
arch-chroot /mnt echo "KEYMAP=$keymap" > /etc/vconsole.conf

# 5.3. Network configuration
arch-chroot /mnt echo "$hostname" > /etc/hostname

# 5.4. Generate initramfs
arch-chroot /mnt mkinitcpio -P

# 5.5. Root password
arch-chroot /mnt echo "root:$root_password" | chpasswd

# 5.6. Create user
arch-chroot /mnt useradd -mG wheel -s /bin/bash "$username"
arch-chroot /mnt echo "$username:$user_password" | chpasswd

# 5.7. Sudo
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers

# 5.8. Grub
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# 5.9. Enable services
arch-chroot /mnt systemctl enable NetworkManager

# 6. Cleanup and exit

# 6.1. Unmount
umount -R /mnt

cleanup
exit 0