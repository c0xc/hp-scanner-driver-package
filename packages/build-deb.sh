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

# Avoid debconf prompts (e.g. tzdata) in CI/container builds.
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

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

# Repair the broken Qt migration hunk in base/utils.py before validation.
python3 - <<'PY'
from pathlib import Path

path = Path("base/utils.py")
text = path.read_text()
old = '''def checkPyQtImport4():
        import ui5
    else:
        log.debug("HPLIP is not installed properly or is installed without graphical support. Please reinstall HPLIP again")
'''
new = '''def checkPyQtImport4():
    try:
        import PyQt5
        import ui5
        return True
    except ImportError as e:
        log.debug(e)
        log.debug("HPLIP is not installed properly or is installed without graphical support. Please reinstall HPLIP again")
        return False
'''
if old not in text:
    raise SystemExit("Failed to locate broken checkPyQtImport4() block")
path.write_text(text.replace(old, new, 1))
PY

# Validate patched Python sources before packaging.
# Exclude legacy ui4 sources because this package is built with Qt4 disabled.
echo "Validating Python syntax..."
find . -path "./ui4" -prune -o -type f -name "*.py" -print0 | xargs -0 -r python3 -m py_compile
find . -type d -name "__pycache__" -prune -exec rm -rf {} +
find . -type f -name "*.py[co]" -delete

# Setup debian/ packaging
echo "Setting up debian/ packaging..."
cp -r "$SCRIPT_DIR/debian" ./

# Mirror the upstream patch series into debian/patches so 3.0 (quilt)
# source packages accurately describe the modified upstream tree.
mkdir -p debian/patches
: > debian/patches/series
while IFS= read -r patch_name; do
    case "$patch_name" in
        ""|\#*)
            continue
            ;;
    esac

    cp "$SCRIPT_DIR/patches/$patch_name" "debian/patches/$patch_name"
    printf '%s\n' "$patch_name" >> debian/patches/series
done < "$SCRIPT_DIR/patches/series"

python3 - <<'PY'
from pathlib import Path

fixed_block = '''def checkPyQtImport4():
    try:
        import PyQt5
        import ui5
        return True
    except ImportError as e:
        log.debug(e)
        log.debug("HPLIP is not installed properly or is installed without graphical support. Please reinstall HPLIP again")
        return False
'''
broken_block = '''def checkPyQtImport4():
        import ui5
    else:
        log.debug("HPLIP is not installed properly or is installed without graphical support. Please reinstall HPLIP again")
'''

path = Path("base/utils.py")
fixed_text = path.read_text()
if fixed_block not in fixed_text:
    raise SystemExit("Failed to locate repaired checkPyQtImport4() block")

broken_text = fixed_text.replace(fixed_block, broken_block, 1)
Path(".debian-patch-old").write_text(broken_text)
Path(".debian-patch-new").write_text(fixed_text)
PY
cat > debian/patches/03-fix-checkpyqtimport4.patch <<'EOF'
Description: fix broken Qt5 import helper after Qt migration patch
Author: c0xc <c0xc@example.com>
Forwarded: not-needed
Last-Update: 2026-03-09

EOF
diff -u --label a/base/utils.py --label b/base/utils.py .debian-patch-old .debian-patch-new >> debian/patches/03-fix-checkpyqtimport4.patch || true
rm -f .debian-patch-old .debian-patch-new
printf '%s\n' 03-fix-checkpyqtimport4.patch >> debian/patches/series

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
apt-get build-dep -y -q .

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
echo "Installing package..."
dpkg -i "$DEB_FILE" > "$OUTPUT_DIR/install-stdout-${DISTRO}.log" 2> "$OUTPUT_DIR/install-stderr-${DISTRO}.log" || {
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
