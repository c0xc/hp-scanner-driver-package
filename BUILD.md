# Build Instructions

## Quick Start

```bash
./build.sh                  # Build all packages (5 variants)
./build.sh ubuntu-22.04     # Build for Mint 21.x / Ubuntu 22.04
./build.sh ubuntu-20.04     # Build for Mint 20.x / Ubuntu 20.04
./build.sh fedora-39        # Build for Fedora 39
./build.sh opensuse-15.5    # Build for openSUSE Leap 15.5
./build.sh all-deb          # Build all DEB variants (3)
./build.sh all-rpm          # Build all RPM variants (2)
./build.sh clean            # Remove artifacts
```

Output: `output/hp-scanner-driver_*.{deb,rpm}` with distro-specific names

---

## Supported Distributions

### DEB Packages

| Distro | Containerfile | Package Example |
|--------|---------------|-----------------|
| Debian 12 | `Containerfile.debian-12` | `hp-scanner-driver_3.25.8-1~debian-12_amd64.deb` |
| Ubuntu 20.04 | `Containerfile.ubuntu-20.04` | `hp-scanner-driver_3.25.8-1~ubuntu-20.04_amd64.deb` |
| Ubuntu 22.04 | `Containerfile.ubuntu-22.04` | `hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb` |

**Mint Compatibility:**
- Mint 20.x → Use `ubuntu-20.04` build
- Mint 21.x → Use `ubuntu-22.04` build

### RPM Packages

| Distro | Containerfile | Package Example |
|--------|---------------|-----------------|
| Fedora 39 | `Containerfile.fedora-39` | `hp-scanner-driver-3.25.8-1.fc39.x86_64.rpm` |
| openSUSE Leap 15.5 | `Containerfile.opensuse-15.5` | `hp-scanner-driver-3.25.8-1.lp155.x86_64.rpm` |

**openSUSE Compatibility:**
- Build for 15.5 works on Leap 15.3, 15.4, 15.5, 15.6 (all binary-compatible)

---

## Manual Build

### Single Distro

```bash
# Build container
podman build -t hp-scanner-driver-ubuntu-22.04-builder -f Containerfile.ubuntu-22.04 .

# Run build
podman run --rm -v ./output:/build/output hp-scanner-driver-ubuntu-22.04-builder [VERSION]
```

### All Variants

```bash
# Build all containers and packages
./build.sh all

# Or build step by step
for f in Containerfile.*; do
    distro=${f#Containerfile.}
    podman build -t hp-scanner-driver-${distro}-builder -f $f .
done
```

Default VERSION is `latest` (reads from VERSION file, currently 3.25.8).

---

## Build Environment

| Containerfile | Base Image | Package Type |
|---------------|------------|--------------|
| Containerfile.debian-12 | debian:bookworm-slim | DEB |
| Containerfile.ubuntu-20.04 | ubuntu:focal | DEB |
| Containerfile.ubuntu-22.04 | ubuntu:jammy | DEB |
| Containerfile.fedora-39 | fedora:39 | RPM |
| Containerfile.opensuse-15.5 | opensuse/leap:15.5 | RPM |

---

## Output Files

After building all variants, `output/` contains:

```
output/
├── hp-scanner-driver_3.25.8-1~debian-12_amd64.deb
├── hp-scanner-driver_3.25.8-1~ubuntu-20.04_amd64.deb
├── hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb
├── hp-scanner-driver-3.25.8-1.fc39.x86_64.rpm
├── hp-scanner-driver-3.25.8-1.lp155.x86_64.rpm
├── install-stdout-*.log      # Installation test logs
└── install-stderr-*.log      # Installation test logs
```

---

## Testing Installation

### In Container (Automatic)

Each build automatically tests installation inside the container. Check logs:
```bash
cat output/install-stderr-ubuntu-22.04.log  # Should be empty
cat output/install-stdout-ubuntu-22.04.log  # Shows installed files
```

### On Host System (Manual)

```bash
# For Mint 21.x / Ubuntu 22.04
cd output
sudo apt install ./hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb

# Verify installation
hp-check -t
scanimage -L

# Remove
sudo apt remove hp-scanner-driver
```
