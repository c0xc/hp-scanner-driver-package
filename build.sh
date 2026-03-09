#!/bin/bash
# hp-scanner-driver build wrapper
# Usage: ./build.sh [distro] [VERSION]
#
# Distros:
#   debian-11       - Debian 11 (Bullseye)
#   debian-12       - Debian 12 (Bookworm)
#   ubuntu-20.04    - Ubuntu 20.04 LTS / Mint 20.x
#   ubuntu-22.04    - Ubuntu 22.04 LTS / Mint 21.x
#   fedora-39       - Fedora 39
#   fedora-40       - Fedora 40
#   opensuse-15.5   - openSUSE Leap 15.5
#   rocky-9         - Rocky Linux 9 / AlmaLinux 9 (RHEL 9)
#   all-deb         - Build all DEB variants
#   all-rpm         - Build all RPM variants
#   all             - Build all variants (default)
#   clean           - Remove build artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p output

DISTRO="${1:-all}"
VERSION="${2:-latest}"

# Container engine (prefer podman, fallback docker)
# Allow override via OCI_BIN or CONTAINER_ENGINE.
OCI_BIN="${OCI_BIN:-${CONTAINER_ENGINE:-}}"
if [ -z "$OCI_BIN" ]; then
    if command -v podman >/dev/null 2>&1; then
        OCI_BIN=podman
    elif command -v docker >/dev/null 2>&1; then
        OCI_BIN=docker
    else
        echo "Error: neither podman nor docker found in PATH" >&2
        exit 127
    fi
fi

build_deb() {
    local distro="$1"
    local version="$2"
    echo "=== Building DEB package for $distro ==="
    "$OCI_BIN" build -t hp-scanner-driver-${distro}-builder -f Containerfile.${distro} .
    "$OCI_BIN" run --rm \
        -e DEBIAN_FRONTEND=noninteractive -e TZ=Etc/UTC \
        -v ./output:/build/output \
        hp-scanner-driver-${distro}-builder "$version"
    echo "=== DEB build complete for $distro ==="
}

build_rpm() {
    local distro="$1"
    local version="$2"
    echo "=== Building RPM package for $distro ==="
    "$OCI_BIN" build -t hp-scanner-driver-${distro}-builder -f Containerfile.${distro} .
    "$OCI_BIN" run --rm \
        -e DEBIAN_FRONTEND=noninteractive -e TZ=Etc/UTC \
        -v ./output:/build/output \
        hp-scanner-driver-${distro}-builder "$version"
    echo "=== RPM build complete for $distro ==="
}

clean() {
    echo "=== Cleaning build artifacts ==="
    rm -f output/*.deb output/*.rpm output/*.log output/*.dsc output/*.tar.xz output/*.src.rpm
    rm -rf output/hplip-*/
    # Remove old container images
    "$OCI_BIN" rmi hp-scanner-driver-debian-11-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-debian-12-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-ubuntu-20.04-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-ubuntu-22.04-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-fedora-39-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-fedora-40-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-opensuse-15.5-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-rocky-9-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-deb-builder 2>/dev/null || true
    "$OCI_BIN" rmi hp-scanner-driver-rpm-builder 2>/dev/null || true
    echo "=== Clean complete ==="
}

list_distros() {
    echo "Available distros:"
    echo "  DEB:"
    echo "    debian-11       - Debian 11 (Bullseye)"
    echo "    debian-12       - Debian 12 (Bookworm)"
    echo "    ubuntu-20.04    - Ubuntu 20.04 LTS / Mint 20.x"
    echo "    ubuntu-22.04    - Ubuntu 22.04 LTS / Mint 21.x"
    echo "  RPM:"
    echo "    fedora-39       - Fedora 39"
    echo "    fedora-40       - Fedora 40"
    echo "    opensuse-15.5   - openSUSE Leap 15.5"
    echo "    rocky-9         - Rocky Linux 9 / AlmaLinux 9 (RHEL 9)"
    echo "  Shortcuts:"
    echo "    all-deb         - Build all DEB variants"
    echo "    all-rpm         - Build all RPM variants"
    echo "    all             - Build all variants (default)"
    echo "    clean           - Remove build artifacts"
}

case "$DISTRO" in
    debian-11)
        build_deb "debian-11" "$VERSION"
        ;;
    debian-12)
        build_deb "debian-12" "$VERSION"
        ;;
    ubuntu-20.04)
        build_deb "ubuntu-20.04" "$VERSION"
        ;;
    ubuntu-22.04)
        build_deb "ubuntu-22.04" "$VERSION"
        ;;
    fedora-39)
        build_rpm "fedora-39" "$VERSION"
        ;;
    fedora-40)
        build_rpm "fedora-40" "$VERSION"
        ;;
    opensuse-15.5)
        build_rpm "opensuse-15.5" "$VERSION"
        ;;
    rocky-9)
        build_rpm "rocky-9" "$VERSION"
        ;;
    all-deb)
        build_deb "debian-11" "$VERSION"
        build_deb "debian-12" "$VERSION"
        build_deb "ubuntu-20.04" "$VERSION"
        build_deb "ubuntu-22.04" "$VERSION"
        ;;
    all-rpm)
        build_rpm "fedora-39" "$VERSION"
        build_rpm "fedora-40" "$VERSION"
        build_rpm "opensuse-15.5" "$VERSION"
        build_rpm "rocky-9" "$VERSION"
        ;;
    all)
        build_deb "debian-11" "$VERSION"
        build_deb "debian-12" "$VERSION"
        build_deb "ubuntu-20.04" "$VERSION"
        build_deb "ubuntu-22.04" "$VERSION"
        build_rpm "fedora-39" "$VERSION"
        build_rpm "fedora-40" "$VERSION"
        build_rpm "opensuse-15.5" "$VERSION"
        build_rpm "rocky-9" "$VERSION"
        ;;  
    clean)
        clean
        ;;
    help|--help|-h)
        list_distros
        ;;
    *)
        echo "Unknown distro: $DISTRO"
        echo ""
        list_distros
        echo ""
        echo "Examples:"
        echo "  $0 ubuntu-22.04           # Build for Mint 21.x"
        echo "  $0 ubuntu-20.04           # Build for Ubuntu 20.04 / Mint 20.x"
        echo "  $0 fedora-39              # Build for Fedora 39"
        echo "  $0 all-deb                # Build all DEB variants"
        echo "  $0 all-rpm 3.25.8         # Build all RPM for specific version"
        exit 1
        ;;
esac
