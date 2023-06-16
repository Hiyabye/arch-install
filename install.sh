#!/bin/bash
set -Eeuo pipefail

# Colors
NOFORMAT='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'

# Function to print messages with color
msg() {
  echo >&2 -e "${1-}"
}

# 0. Introduction
msg
msg "${BLUE}Welcome to Arch Linux Installer!${NOFORMAT}"
msg
msg "${YELLOW}WARNING: This script will remove all existing data on the disk${NOFORMAT}"
msg "${YELLOW}WARNING: This script is experimental and is not verified${NOFORMAT}"
msg "${YELLOW}WARNING: This script is not intended for use in production${NOFORMAT}"
msg

# 1. Prepare environment

# 1.1. Update system clock
msg "${BLUE}Updating system clock...${NOFORMAT}"
msg
timedatectl set-ntp true
msg

# 1.2. Install dependencies
msg "${BLUE}Installing dependencies...${NOFORMAT}"
msg
pacman -Sy --noconfirm --needed reflector
msg

# 1.3. Update mirror list
msg "${BLUE}Updating mirror list... This might take a while...${NOFORMAT}"
msg
reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
msg

# 2. User credentials

# 2.1. Hostname
read -p "Enter hostname: " hostname
[[ -n "$hostname" ]] || { echo "Hostname cannot be empty"; exit 1; }
msg

# 2.2. Root password
read -s -p "Enter admin password: " root_password
[[ -n "$root_password" ]] || { echo "Admin password cannot be empty"; exit 1; }
msg
read -s -p "Enter admin password again: " root_password2
[[ "$root_password" == "$root_password2" ]] || { echo "Passwords do not match"; exit 1; }
msg

# 2.3. Username
read -p "Enter username: " username
[[ -n "$username" ]] || { echo "Username cannot be empty"; exit 1; }
msg

# 2.4. User password
read -s -p "Enter user password: " user_password
[[ -n "$user_password" ]] || { echo "User password cannot be empty"; exit 1; }
msg
read -s -p "Enter user password again: " user_password2
[[ "$user_password" == "$user_password2" ]] || { echo "Passwords do not match"; exit 1; }
msg

# 2.5. Timezone
read -p "Enter timezone (e.g. Asia/Seoul): " timezone
[[ -n "$timezone" ]] || { echo "Timezone cannot be empty"; exit 1; }
msg

# 2.6. Locale
read -p "Enter locale (e.g. en_US.UTF-8): " locale
[[ -n "$locale" ]] || { echo "Locale cannot be empty"; exit 1; }
msg

# 3. Disk partitioning

# 3.1. Disk name
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
msg "${BLUE}Select installation disk:${NOFORMAT}"

options=()
while read -r line; do
  disk_name=$(echo "$line" | awk '{print $1}')
  disk_size=$(echo "$line" | awk '{print $2}')
  options+=("$disk_name $disk_size")
done <<< "$devicelist"

select device_option in "${options[@]}"; do
  [[ -n "$device_option" ]] || { echo "Invalid option. Aborted."; exit 1; }
  device=$(echo "$device_option" | awk '{print $1}')
  break
done
msg

# 3.2. Partition the disks
msg "${BLUE}Partitioning the disks...${NOFORMAT}"
parted --script "$device" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB \
  set 1 boot on \
  mkpart primary linux-swap 513MiB 4GiB \
  mkpart primary ext4 4GiB 100%
msg

# 3.3. Format the partitions
part_boot="${device}1"
part_swap="${device}2"
part_root="${device}3"

msg "${BLUE}Formatting the partitions...${NOFORMAT}"
wipefs "$part_boot"
wipefs "$part_swap"
wipefs "$part_root"
msg

msg "${BLUE}Creating file systems...${NOFORMAT}"
mkfs.vfat -F32 "$part_boot"
mkswap "$part_swap"
mkfs.ext4 "$part_root"
msg

# 3.4. Mount the file systems
msg "${BLUE}Mounting the file systems...${NOFORMAT}"
swapon "$part_swap"
mount "$part_root" /mnt
mkdir /mnt/boot
mount "$part_boot" /mnt/boot
msg

# 4. Install the base packages

# 4.1. Enable parallel downloads
msg "${BLUE}Enabling parallel downloads...${NOFORMAT}"
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 5/" /etc/pacman.conf
msg

# 4.2. Install base packages
msg "${BLUE}Installing base packages...${NOFORMAT}"
pacstrap /mnt base base-devel linux linux-firmware nano networkmanager efibootmgr grub os-prober intel-ucode sudo git neofetch
msg

# 4.3. Generate fstab
msg "${BLUE}Generating fstab...${NOFORMAT}"
genfstab -U /mnt >> /mnt/etc/fstab
msg

# 5. Chroot

# 5.1. Time zone
msg "${BLUE}Configuring time zone...${NOFORMAT}"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
arch-chroot /mnt hwclock --systohc
msg

# 5.2. Localization
msg "${BLUE}Configuring localization...${NOFORMAT}"
arch-chroot /mnt sed -i "s/#$locale/$locale/" /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=$locale" > /etc/locale.conf
msg

# 5.3. Network configuration
msg "${BLUE}Configuring network...${NOFORMAT}"
arch-chroot /mnt echo "$hostname" > /etc/hostname
arch-chroot /mnt systemctl enable NetworkManager
msg

# 5.4. Generate initramfs
msg "${BLUE}Generating initramfs...${NOFORMAT}"
arch-chroot /mnt mkinitcpio -P
msg

# 5.5. Root password
arch-chroot /mnt echo "root:$root_password" | chpasswd

# 5.6. Create user
arch-chroot /mnt useradd -mG wheel -s /bin/bash "$username"
arch-chroot /mnt echo "$username:$user_password" | chpasswd

# 5.7. Sudo
msg "${BLUE}Configuring sudo...${NOFORMAT}"
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
msg

# 5.8. Grub
msg "${BLUE}Configuring grub...${NOFORMAT}"
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
msg

# 6. Cleanup and exit
msg "${BLUE}Cleanup and exit...${NOFORMAT}"
umount -R /mnt
exit 0