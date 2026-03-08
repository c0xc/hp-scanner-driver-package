# hp-scanner-driver

Have you ever tried to install HP's driver for an HP scanner or printer, but failed to do so because the official Terminal-based interactive installer has syntax errors? Or it tried to install dependencies which were dropped from the OS repo years ago (Qt4)?

The hplip package in the OS repository is too old for your printer according to the HP support matrix.

Then you downloaded their official source tarball only to find out that you would have to build and run "make install" (after installing build tools... for a printer)? You might be wondering how to uninstall it later in a clean way when it breaks or a new version is available?

This is the motivation for hp-scanner-driver: Pre-built packages for your specific Linux distribution that install cleanly via apt/dnf/zypper and can be removed cleanly. Try it if the official hplip package is not working for you, before you attempt to "make install" shoot your computer. Use at your own risk, no warranty (just like hplip itself).

This is an automated open-source rebuild. It downloads the official hplip source tarball and packages it for your distribution.

Maintainer: c0xc
Disclaimer: Unofficial package. Not affiliated with or endorsed by HP. HP is great, most of the time.

---

## Installation

### Linux Mint 21.x / Ubuntu 22.04

    wget https://github.com/c0xc/hplip-packages/releases/download/v3.25.8/hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb
    sudo apt install ./hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb

### Linux Mint 20.x / Ubuntu 20.04

    wget https://github.com/c0xc/hplip-packages/releases/download/v3.25.8/hp-scanner-driver_3.25.8-1~ubuntu-20.04_amd64.deb
    sudo apt install ./hp-scanner-driver_3.25.8-1~ubuntu-20.04_amd64.deb

### Debian 12

    wget https://github.com/c0xc/hplip-packages/releases/download/v3.25.8/hp-scanner-driver_3.25.8-1~debian-12_amd64.deb
    sudo apt install ./hp-scanner-driver_3.25.8-1~debian-12_amd64.deb

### Fedora 39

    wget https://github.com/c0xc/hplip-packages/releases/download/v3.25.8/hp-scanner-driver-3.25.8-1.fc39.x86_64.rpm
    sudo dnf install ./hp-scanner-driver-3.25.8-1.fc39.x86_64.rpm

### openSUSE Leap 15.x

    wget https://github.com/c0xc/hplip-packages/releases/download/v3.25.8/hp-scanner-driver-3.25.8-1.lp155.x86_64.rpm
    sudo zypper install ./hp-scanner-driver-3.25.8-1.lp155.x86_64.rpm

---

## Which Package Should I Choose?

Linux Mint 21.3, 21.2, 21.1, 21 ... use ubuntu-22.04
Linux Mint 20.3, 20.2, 20.1, 20 ... use ubuntu-20.04
Ubuntu 24.04, 22.04 ... use ubuntu-22.04
Ubuntu 20.04 ... use ubuntu-20.04
Debian 12 (Bookworm) ... use debian-12
Debian 11 (Bullseye) ... use debian-12 (should work)
Fedora 39 ... use fedora-39
Fedora 38 ... use fedora-39 (should work)
openSUSE Leap 15.3 - 15.6 ... use opensuse-15.5

Not sure? Check your OS version:

    # Debian/Ubuntu/Mint
    lsb_release -d

    # Fedora
    cat /etc/fedora-release

    # openSUSE
    cat /etc/os-release

---

## Features

- Distribution-specific builds - Built for your exact distro version
- Clean installation - Uses native package manager (apt/dnf/zypper)
- Clean removal - apt remove hp-scanner-driver removes everything
- Qt5 support - Works on modern systems (no Qt4 dependency)
- SANE scanner support - Proper drop-in config, no file conflicts
- All HPLIP tools included - hp-setup, hp-check, HP Toolbox GUI

---

## Important Notes

### Proprietary Plugin Requirement

Some HP devices (particularly Color LaserJet MFP series) require a proprietary plugin for scanning functionality. If scanning fails with "Error during device I/O", install the plugin:

    hp-plugin -i

The plugin prompt may appear automatically on first scan attempt. (Or not, ask HP.)

---

## Documentation

- README.md - This file (installation and usage)
- BUILD.md - Build instructions for maintainers
- TEST.md - Test report and verification results
- PAIN.md - Known issues and troubleshooting

---

License: GPL-2.0-or-later / LGPL-2.1-or-later (from HP sources)
