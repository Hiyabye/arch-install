# Arch Linux Installation Guide

## How to use

1. Boot into the Arch Linux live environment.

2. Connect to the internet.

```bash
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect <SSID>
exit
```

3. Install dependencies.
  
```bash 
pacman-key --init
pacman -Sy --noconfirm --needed git
```

4. Download and run the `install.sh` script.

```bash
git clone https://github.com/Hiyabye/arch-install.git
cd arch-install
chmod +x install.sh
./install.sh
```

5. After the script finishes, reboot the system.

```bash
shutdown now
```

6. Remove the installation media and boot into the new system.

```bash
# After logging in as the new user
# Connect to a network
nmcli device wifi connect <SSID> password <password>
```

## References

- [Installation Guide - ArchWiki](https://wiki.archlinux.org/title/Installation_guide)
- [Automating Arch Linux Part 3: Creating a Custom Arch Linux Installer | Disconnected Systems](https://disconnected.systems/blog/archlinux-installer/#setting-variables-and-collecting-user-input)

## Roadmap

- [ ] Successfully install Arch Linux
- [ ] Move time consuming tasks to the end
- [ ] Add option to install a desktop environment

## License

This project is licensed under the [MIT License](LICENSE).