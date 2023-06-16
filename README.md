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

3. Download and run the `install.sh` script.

```bash
curl -L https://github.com/Hiyabye/arch-install/install.sh -o install.sh
chmod +x install.sh
./install.sh
```

4. After the script finishes, reboot the system.

```bash
shutdown now
```

5. Remove the installation media and boot into the new system.

```bash
# After logging in as the new user
# Connect to a network
nmcli device wifi connect <SSID> password <password>
```

## References

- [Installation Guide - ArchWiki](https://wiki.archlinux.org/title/Installation_guide)
- [Automating Arch Linux Part 3: Creating a Custom Arch Linux Installer | Disconnected Systems](https://disconnected.systems/blog/archlinux-installer/#setting-variables-and-collecting-user-input)

## License

This project is licensed under the [MIT License](LICENSE).