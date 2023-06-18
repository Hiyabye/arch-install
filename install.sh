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

# Part 1: Pre-installation

# Introduction
echo
echo -e "${BLUE}Welcome to Arch Linux Installer!${NOFORMAT}"
echo
echo -e "${YELLOW}WARNING: This script will remove all existing data on the disk${NOFORMAT}"
echo -e "${YELLOW}WARNING: This script is experimental and is not verified${NOFORMAT}"
echo -e "${YELLOW}WARNING: This script is not intended for use in production${NOFORMAT}"
echo

# Verify the boot mode
# UEFI will have a directory named /sys/firmware/efi. If not, it's likely using BIOS
echo -e "${BLUE}Verifying boot mode...${NOFORMAT}"
echo
if [ -d /sys/firmware/efi ]; then
  echo "Boot mode: UEFI"
  uefi=1
else
  echo "Boot mode: BIOS"
  uefi=0
fi

# Update the system clock
echo -e "${BLUE}Updating system clock...${NOFORMAT}"
echo
timedatectl set-ntp true
echo

# Identify the target disk(s)
devices=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
echo -e "${BLUE}Available disks:${NOFORMAT}"
echo
echo "$devices"
echo
read -p "Enter the target disk (e.g. /dev/sda): " device
echo

# Confirm the target disk(s)
echo -e "${BLUE}The following disk(s) will be wiped:${NOFORMAT}"
echo
echo "$device"
echo
read -p "Are you sure? [y/N] " confirm
[[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]] || { echo "Aborted"; exit 1; }
echo

# Partition the disks
echo -e "${BLUE}Partitioning disks...${NOFORMAT}"
echo
if [ $uefi -eq 1 ]; then
  # For UEFI system, create an EFI System Partition (ESP) and a root partition at minimum
  parted -s "$device" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 boot on \
    mkpart primary ext4 513MiB 100%
else
  # For BIOS system, create a root partition only
  parted -s "$device" mklabel msdos \
    mkpart primary ext4 1MiB 100%
fi
echo

# Format the partitions
echo -e "${BLUE}Formatting partitions...${NOFORMAT}"
echo
if [ $uefi -eq 1 ]; then
  # For UEFI system, format the ESP as fat32 and the root partition as ext4
  mkfs.vfat -F 32 "${device}1"
  mkfs.ext4 "${device}2"
else
  # For BIOS system, format the root partition as ext4
  mkfs.ext4 "${device}1"
fi
echo

# Mount the file systems
echo -e "${BLUE}Mounting file systems...${NOFORMAT}"
echo
if [ $uefi -eq 1 ]; then
  # For UEFI system, mount the root partition to /mnt and the ESP to /mnt/boot
  mount "${device}2" /mnt
  mkdir -p /mnt/boot
  mount "${device}1" /mnt/boot
else
  # For BIOS system, mount the root partition to /mnt
  mount "${device}1" /mnt
fi
echo

# Part 2: Installation

# Select the mirrors
echo -e "${BLUE}Selecting mirrors...${NOFORMAT}"
echo
pacman -Sy --noconfirm reflector
reflector --verbose --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
echo

# Enable parallel downloads
echo -e "${BLUE}Enabling parallel downloads...${NOFORMAT}"
echo
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
echo

# Install essential packages
echo -e "${BLUE}Installing essential packages...${NOFORMAT}"
echo
pacstrap /mnt base linux linux-firmware base-devel intel-ucode nano btrfs-progs git
echo

# Part 3: Configuration

# Generate Fstab file
echo -e "${BLUE}Generating fstab file...${NOFORMAT}"
echo
genfstab -U /mnt >> /mnt/etc/fstab
echo

# Time zone
echo -e "${BLUE}Configuring time zone...${NOFORMAT}"
echo
read -p "Enter the time zone (Region/City): " timezone
arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$timezone" /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo

# Localization
echo -e "${BLUE}Configuring localization...${NOFORMAT}"
echo
arch-chroot /mnt sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf
echo "KEYMAP=us" >> /mnt/etc/vconsole.conf
echo

# Network configuration
echo -e "${BLUE}Configuring network...${NOFORMAT}"
echo
pacman -S --noconfirm networkmanager
arch-chroot /mnt systemctl enable NetworkManager
read -p "Enter the hostname: " hostname
echo "$hostname" > /mnt/etc/hostname
arch-chroot /mnt cat <<EOF > /mnt/etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname.localdomain $hostname
EOF
echo

# Initramfs
echo -e "${BLUE}Creating initramfs...${NOFORMAT}"
echo
arch-chroot /mnt mkinitcpio -P
echo

# Root password
echo -e "${BLUE}Configuring root password...${NOFORMAT}"
echo
read -s -p "Enter the root password: " root_password
echo
read -s -p "Confirm the root password: " root_password_confirm
echo
if [ "$root_password" != "$root_password_confirm" ]; then
  echo -e "${RED}Passwords do not match${NOFORMAT}"
  exit 1
fi
arch-chroot /mnt echo "root:$root_password" | chpasswd
echo

# Create a new user
echo -e "${BLUE}Creating a new user...${NOFORMAT}"
echo
read -p "Enter the username: " username
arch-chroot /mnt useradd -mG wheel -s /bin/bash "$username"
read -s -p "Enter the password for $username: " user_password
echo
read -s -p "Confirm the password for $username: " user_password_confirm
echo
if [ "$user_password" != "$user_password_confirm" ]; then
  echo -e "${RED}Passwords do not match${NOFORMAT}"
  exit 1
fi
arch-chroot /mnt echo "username:password" | chpasswd
echo

# Sudoers
echo -e "${BLUE}Configuring sudoers...${NOFORMAT}"
echo
pacman -S --noconfirm sudo
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
echo

# Install and configure systemd-boot
echo -e "${BLUE}Installing and configuring systemd-boot...${NOFORMAT}"
echo
arch-chroot /mnt bootctl --path=/boot install
arch-chroot /mnt cat <<EOF > /boot/loader/loader.conf
default arch
timeout 1
console-mode max
editor no
EOF
if [ $uefi -eq 1 ]; then
  arch-chroot /mnt cat <<EOF > /boot/loader/entries/arch.conf
  title Arch Linux
  linux /vmlinuz-linux
  initrd /intel-ucode.img
  initrd /initramfs-linux.img
  options root=PARTUUID=$(blkid -s PARTUUID -o value "${device}2") rw
EOF
else
  arch-chroot /mnt cat <<EOF > /boot/loader/entries/arch.conf
  title Arch Linux
  linux /vmlinuz-linux
  initrd /intel-ucode.img
  initrd /initramfs-linux.img
  options root=PARTUUID=$(blkid -s PARTUUID -o value "${device}1") rw
EOF
fi
echo

# Part 4: Finalize

# Unmount
echo -e "${BLUE}Unmounting...${NOFORMAT}"
umount -R /mnt
echo

echo -e "${GREEN}Done! You can now reboot.${NOFORMAT}"
echo -e "${GREEN}Don't forget to remove the installation media.${NOFORMAT}"