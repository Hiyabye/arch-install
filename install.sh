#!/bin/bash
set -Eeuo pipefail

# Colors
NOFORMAT='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'

##########################################
######## Part 1: Pre-installation ########
##########################################

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
echo -e "[1/18] ${BLUE}Verifying boot mode...${NOFORMAT}"
echo
if [ -d /sys/firmware/efi ]; then
  echo "Boot mode: UEFI"
  uefi=1
else
  echo "Boot mode: BIOS"
  uefi=0
fi
echo

# Update the system clock
echo -e "[2/18] ${BLUE}Updating system clock...${NOFORMAT}"
timedatectl set-ntp true
echo

# Identify the target disk(s)
devices=$(lsblk -dplnx size -o name | grep -Ev "boot|rpmb|loop" | tac)
echo -e "${BLUE}Available disks:${NOFORMAT}"
echo
echo "$devices"
echo
select device in $devices; do
  if [ -n "$device" ]; then
    break
  else
    echo "Invalid selection"
  fi
done < /dev/tty
echo

# Confirm the target disk(s)
echo -e "${BLUE}The following disk(s) will be wiped:${NOFORMAT}"
echo
echo "$device"
echo
read -p "Are you sure? [y/N] " confirm < /dev/tty
[[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]] || { echo "Aborted"; exit 1; }
echo

# Partition the disks
echo -e "[3/18] ${BLUE}Partitioning disks...${NOFORMAT}"
if [ $uefi -eq 1 ]; then
  # For UEFI system, create an EFI System Partition (ESP) and a root partition at minimum
  parted -s "$device" mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 boot on \
    mkpart primary btrfs 513MiB 100%
else
  # For BIOS system, create a root partition only
  parted -s "$device" mklabel msdos \
    mkpart primary btrfs 1MiB 100%
fi
echo

# Format the partitions
echo -e "[4/18] ${BLUE}Formatting partitions...${NOFORMAT}"
echo
if [ $uefi -eq 1 ]; then
  # For UEFI system, format the ESP as fat32 and the root partition as btrfs
  mkfs.vfat -F 32 "${device}1"
  mkfs.btrfs -f "${device}2"
else
  # For BIOS system, format the root partition as btrfs
  mkfs.btrfs -f "${device}1"
fi
echo

# Create the Btrfs subvolumes
echo -e "[5/18] ${BLUE}Creating Btrfs subvolumes...${NOFORMAT}"
echo
if [ $uefi -eq 1 ]; then
  # For UEFI system, create subvolumes for root, home, and snapshots
  mount "${device}2" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@var
  btrfs subvolume create /mnt/@snapshots
  umount /mnt
else
  # For BIOS system, create subvolumes for root, home, and snapshots
  mount "${device}1" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@var
  btrfs subvolume create /mnt/@snapshots
  umount /mnt
fi
echo

# Mount the file systems
echo -e "[6/18] ${BLUE}Mounting file systems...${NOFORMAT}"
if [ $uefi -eq 1 ]; then
  # For UEFI system, mount the root partition to /mnt and the ESP to /mnt/boot
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@ "${device}2" /mnt
  mkdir -p /mnt/{boot,home,var,swap,.snapshots}
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@home "${device}2" /mnt/home
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@var "${device}2" /mnt/var
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots "${device}2" /mnt/.snapshots
  mount "${device}1" /mnt/boot
else
  # For BIOS system, mount the root partition to /mnt
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@ "${device}1" /mnt
  mkdir -p /mnt/{home,var,swap,.snapshots}
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@home "${device}1" /mnt/home
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@var "${device}1" /mnt/var
  mount -o defaults,noatime,nodiratime,compress=zstd,discard=async,space_cache=v2,subvol=@snapshots "${device}1" /mnt/.snapshots
fi
echo

######################################
######## Part 2: Installation ########
######################################

# Select the mirrors
echo -e "[7/18] ${BLUE}Selecting mirrors...${NOFORMAT}"
echo
reflector --verbose --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
echo

# Enable parallel downloads
echo -e "[8/18] ${BLUE}Enabling parallel downloads...${NOFORMAT}"
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
echo

# Install essential packages
echo -e "[9/18] ${BLUE}Installing essential packages...${NOFORMAT}"
echo
pacstrap -K /mnt base linux linux-firmware base-devel intel-ucode nano dosfstools btrfs-progs git
echo

#######################################
######## Part 3: Configuration ########
#######################################

# Generate Fstab file
echo -e "[10/18] ${BLUE}Generating fstab file...${NOFORMAT}"
genfstab -U /mnt >> /mnt/etc/fstab
echo

# Time zone
echo -e "[11/18] ${BLUE}Configuring time zone...${NOFORMAT}"
echo
read -p "Enter the time zone (Region/City): " timezone < /dev/tty
ln -sf "/mnt/usr/share/zoneinfo/$timezone" /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc
echo

# Localization
echo -e "[12/18] ${BLUE}Configuring localization...${NOFORMAT}"
echo
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf
echo "KEYMAP=us" >> /mnt/etc/vconsole.conf
echo

# Network configuration
echo -e "[13/18] ${BLUE}Configuring network...${NOFORMAT}"
echo
arch-chroot /mnt pacman -S --noconfirm networkmanager
arch-chroot /mnt systemctl enable NetworkManager.service
echo
read -p "Enter the hostname: " hostname < /dev/tty
echo "$hostname" > /mnt/etc/hostname
cat <<EOF > /mnt/etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname.localdomain $hostname
EOF
echo

# Initramfs
echo -e "[14/18] ${BLUE}Creating initramfs...${NOFORMAT}"
echo
sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck btrfs)/' /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P
echo

# Root password
echo -e "[15/18] ${BLUE}Configuring root...${NOFORMAT}"
echo
read -s -p "Enter the root password: " root_password < /dev/tty
echo
read -s -p "Confirm the root password: " root_password_confirm < /dev/tty
echo
if [ "$root_password" != "$root_password_confirm" ]; then
  echo -e "${RED}Passwords do not match${NOFORMAT}"
  exit 1
fi
arch-chroot /mnt echo "root:$root_password" | chpasswd
echo

# Sudoers
echo -e "[16/18] ${BLUE}Configuring sudoers...${NOFORMAT}"
echo
pacman -S --noconfirm sudo
arch-chroot /mnt sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
echo

# Install and configure systemd-boot
echo -e "[17/18] ${BLUE}Installing and configuring systemd-boot...${NOFORMAT}"
echo
arch-chroot /mnt bootctl --path=/boot install
cat <<EOF > /mnt/boot/loader/loader.conf
default arch
timeout 1
console-mode max
editor no
EOF
if [ $uefi -eq 1 ]; then
  cat <<EOF > /mnt/boot/loader/entries/arch.conf
  title Arch Linux
  linux /vmlinuz-linux
  initrd /intel-ucode.img
  initrd /initramfs-linux.img
  options root=PARTUUID=$(blkid -s PARTUUID -o value "${device}2") rootflags=subvol=@ rw
EOF
else
  cat <<EOF > /mnt/boot/loader/entries/arch.conf
  title Arch Linux
  linux /vmlinuz-linux
  initrd /intel-ucode.img
  initrd /initramfs-linux.img
  options root=PARTUUID=$(blkid -s PARTUUID -o value "${device}1") rootflags=subvol=@ rw
EOF
fi
echo

##################################
######## Part 4: Finalize ########
##################################

# Unmount
echo -e "[18/18] ${BLUE}Unmounting...${NOFORMAT}"
umount -R /mnt
echo

echo -e "${GREEN}Done! You can now reboot.${NOFORMAT}"
echo -e "${GREEN}Don't forget to remove the installation media.${NOFORMAT}"
echo