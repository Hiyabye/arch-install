# Arch Linux Installation Guide

## How to use

1. Boot into the Arch Linux live environment.

2. Connect to the internet using iwctl.

```bash
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect <SSID>
exit
```

3. Download and run the script.

```bash
curl -sL https://raw.githubusercontent.com/Hiyabye/arch-install/main/install.sh | bash
```

4. After the script finishes, shut down the system.

```bash
shutdown now
```

5. Remove the installation media and boot into the new system.
After logging in as the new user, connect to the internet using nmcli.

```bash
nmcli device wifi connect <SSID> password <password>
```

6. Run the post-install script.

```bash
curl -sL https://raw.githubusercontent.com/Hiyabye/arch-install/main/post-install.sh | bash
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