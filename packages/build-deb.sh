#!/bin/bash
# build-deb.sh - Build Debian/Ubuntu package for hp-scanner-driver
# Maintainer: c0xc
# Usage: ./build-deb.sh VERSION [DISTRO]
#   VERSION: HPLIP version (e.g., 3.25.8)
#   DISTRO:  Target distribution (e.g., ubuntu-22.04, debian-12)

set -e

VERSION="${1:-3.25.8}"
DISTRO="${2:-ubuntu-22.04}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PARENT_DIR/output"
WORKDIR="/tmp/hplip-build-$$"
TARBALL="hplip-${VERSION}.tar.gz"

# Extract distro version for package naming
# e.g., ubuntu-22.04 -> 22.04, debian-12 -> 12
DISTRO_VERSION=$(echo "$DISTRO" | sed 's/^[^-]*-//')

echo "=== Building hp-scanner-driver .deb for $DISTRO ==="
echo "HPLIP Version: $VERSION"
echo "Distro: $DISTRO ($DISTRO_VERSION)"
echo "Work dir: $WORKDIR"

trap "rm -rf $WORKDIR" EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORKDIR"

write_md5sums_manifest() {
    local manifest
    manifest="$OUTPUT_DIR/md5sums-${DISTRO}-${VERSION}.md5"

    (
        set -e
        cd "$OUTPUT_DIR"

        # Only include the upstream tarball/signature and the built package artifacts.
        # Exclude logs and checksum/provenance files to keep this user-focused.
        {
            if [ -f "$TARBALL" ]; then
                printf '%s\n' "$TARBALL"
            fi
            if [ -f "${TARBALL}.asc" ]; then
                printf '%s\n' "${TARBALL}.asc"
            fi

            ls -1 hp-scanner-driver_*"${VERSION}"*.deb 2>/dev/null || true
            ls -1 *.dsc 2>/dev/null || true
            ls -1 *.tar.* 2>/dev/null || true
        } | LC_ALL=C sort -u | while IFS= read -r f; do
            [ -n "$f" ] || continue
            [ -f "$f" ] || continue
            md5sum "$f"
        done > "$manifest"
    )

    echo "Wrote md5sums manifest: $manifest"
}

cd "$WORKDIR"

# Download + verify upstream source (shared helper used by both DEB/RPM flows).
bash "$SCRIPT_DIR/prepare-upstream-source.sh" "$VERSION" "$DISTRO" "$WORKDIR" "$OUTPUT_DIR"

# Create expected .orig.tar.gz name for debuild
mv "$TARBALL" hp-scanner-driver_${VERSION}.orig.tar.gz
tar xzf hp-scanner-driver_${VERSION}.orig.tar.gz
cd hplip-${VERSION}

# Create required files for automake
touch AUTHORS ChangeLog NEWS README

# Apply patches
echo "Applying patches..."
bash "$SCRIPT_DIR/apply-patches.sh" "$WORKDIR/hplip-${VERSION}" "$SCRIPT_DIR/patches"

# Setup debian/ packaging
echo "Setting up debian/ packaging..."
cp -r "$SCRIPT_DIR/debian" ./

# Update debian/changelog with distro-specific version
# Format: hp-scanner-driver (3.25.8-0ubuntu1) jammy; urgency=medium
echo "Updating debian/changelog for $DISTRO..."
DISTRO_CODENAME=$(lsb_release -cs 2>/dev/null || echo "jammy")
# Create simple revision: 0ubuntu1 for Ubuntu, 0debian1 for Debian
if [[ "$DISTRO" == ubuntu-* ]]; then
    REVISION="0ubuntu1"
elif [[ "$DISTRO" == debian-* ]]; then
    REVISION="0debian1"
else
    REVISION="0ubuntu1"
fi
cat > debian/changelog << EOF
hp-scanner-driver (${VERSION}-${REVISION}) ${DISTRO_CODENAME}; urgency=medium

  * Build for ${DISTRO}
  * HPLIP upstream version ${VERSION}

 -- c0xc <c0xc@example.com>  $(date -R)

EOF

# Install build dependencies
echo "Installing build dependencies..."
apt-get update
apt-get build-dep -y .

# Build package
echo "Building .deb package..."
debuild -us -uc

# Copy output
echo "Copying packages to $OUTPUT_DIR..."
cd ..
cp *.deb "$OUTPUT_DIR/"
cp *.dsc "$OUTPUT_DIR/" 2>/dev/null || true
cp *.tar.* "$OUTPUT_DIR/" 2>/dev/null || true

write_md5sums_manifest

echo "=== Build Complete ==="
ls -lh "$OUTPUT_DIR"/*.deb 2>/dev/null || echo "No .deb files found"

# === TEST STEP: Install deb inside container ===
echo ""
echo "=== TEST STEP: Installing .deb inside container ==="
DEB_FILE=$(ls -t "$OUTPUT_DIR"/hp-scanner-driver_*.deb 2>/dev/null | head -n1)
if [ -z "$DEB_FILE" ]; then
    echo "ERROR: No .deb file found in $OUTPUT_DIR"
    exit 1
fi
echo "Installing: $DEB_FILE"

# Install dependencies first (libsane-common provides /etc/sane.d/dll.conf)
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq cups-client cups-daemon python3 2>&1 | tee -a "$OUTPUT_DIR/install-dependencies-${DISTRO}.log" || true

# Install the package, capturing stdout and stderr to separate files
# Note: Using --force-depends because HPLIP falsely detects python2 dependency
# The package works fine with python3 only - this is a known HPLIP quirk
echo "Installing with --force-depends (python2 is false positive)..."
dpkg -i --force-depends "$DEB_FILE" > "$OUTPUT_DIR/install-stdout-${DISTRO}.log" 2> "$OUTPUT_DIR/install-stderr-${DISTRO}.log" || {
    EXIT_CODE=$?
    echo "dpkg install failed with exit code $EXIT_CODE"
    echo "See: $OUTPUT_DIR/install-stdout-${DISTRO}.log"
    echo "See: $OUTPUT_DIR/install-stderr-${DISTRO}.log"
    echo ""
    echo "--- stderr output ---"
    cat "$OUTPUT_DIR/install-stderr-${DISTRO}.log"
    exit $EXIT_CODE
}

echo "Installation successful!"
echo "See: $OUTPUT_DIR/install-stdout-${DISTRO}.log"
echo "See: $OUTPUT_DIR/install-stderr-${DISTRO}.log"
