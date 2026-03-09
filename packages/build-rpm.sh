#!/bin/bash
# build-rpm.sh - Build RPM package for hp-scanner-driver
# Maintainer: c0xc
# Usage: ./build-rpm.sh VERSION [DISTRO]
#   VERSION: HPLIP version (e.g., 3.25.8)
#   DISTRO:  Target distribution (e.g., fedora-39, opensuse-15.5)

set -e

VERSION="${1:-3.25.8}"
DISTRO="${2:-fedora-39}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PARENT_DIR/output"
WORKDIR="/tmp/hplip-build-$$"
TARBALL="hplip-${VERSION}.tar.gz"

# Extract distro info for package naming
# e.g., fedora-39 -> fc39, opensuse-15.5 -> lp155
if [[ "$DISTRO" == fedora-* ]]; then
    FEDORA_VER="${DISTRO#fedora-}"
    DISTRO_SUFFIX="fc${FEDORA_VER}"
    PKG_MANAGER="dnf"
elif [[ "$DISTRO" == opensuse-* ]]; then
    OPENSUSE_VER="${DISTRO#opensuse-}"
    # Convert 15.5 -> lp155
    OPENSUSE_SHORT=$(echo "$OPENSUSE_VER" | tr -d '.')
    DISTRO_SUFFIX="lp${OPENSUSE_SHORT}"
    PKG_MANAGER="zypper"
elif [[ "$DISTRO" == rocky-* ]]; then
    # Rocky/Alma use el9 format
    ROCKY_VER="${DISTRO#rocky-}"
    DISTRO_SUFFIX="el${ROCKY_VER%%.*}"
    PKG_MANAGER="dnf"
else
    DISTRO_SUFFIX="$DISTRO"
    PKG_MANAGER="unknown"
fi

echo "=== Building hp-scanner-driver .rpm for $DISTRO ==="
echo "HPLIP Version: $VERSION"
echo "Distro: $DISTRO ($DISTRO_SUFFIX)"
echo "Work dir: $WORKDIR"

trap "rm -rf $WORKDIR" EXIT

mkdir -p "$OUTPUT_DIR"

# Set up RPM build directories based on distribution
if [ "$PKG_MANAGER" = "dnf" ]; then
    # Fedora uses ~/rpmbuild
    mkdir -p ~/rpmbuild/SOURCES
    mkdir -p ~/rpmbuild/SPECS
    mkdir -p ~/rpmbuild/BUILD
    mkdir -p ~/rpmbuild/RPMS
    mkdir -p ~/rpmbuild/SRPMS
    RPM_TOP="$HOME/rpmbuild"
elif [ "$PKG_MANAGER" = "zypper" ]; then
    # openSUSE uses /usr/src/packages
    RPM_TOP="/usr/src/packages"
    mkdir -p "$RPM_TOP"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}
else
    RPM_TOP="$HOME/rpmbuild"
    mkdir -p ~/rpmbuild/SOURCES
    mkdir -p ~/rpmbuild/SPECS
    mkdir -p ~/rpmbuild/BUILD
    mkdir -p ~/rpmbuild/RPMS
    mkdir -p ~/rpmbuild/SRPMS
fi

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

            ls -1 hp-scanner-driver-*.rpm 2>/dev/null || true
            ls -1 *.src.rpm 2>/dev/null || true
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

cp "$TARBALL" "$RPM_TOP/SOURCES/"

# Copy and update spec file (use distro-specific spec if available)
if [ -f "$SCRIPT_DIR/rpm/hp-scanner-driver.spec.${DISTRO%%-*}" ]; then
    cp "$SCRIPT_DIR/rpm/hp-scanner-driver.spec.${DISTRO%%-*}" "$RPM_TOP/SPECS/hp-scanner-driver.spec"
else
    cp "$SCRIPT_DIR/rpm/hp-scanner-driver.spec" "$RPM_TOP/SPECS/"
fi
sed -i "s/Version:        3.25.8/Version:        ${VERSION}/g" "$RPM_TOP/SPECS/hp-scanner-driver.spec"

# Prepare source with patches
echo "Preparing source with patches..."
cd "$RPM_TOP/SOURCES"
tar xzf "$TARBALL"
cd hplip-${VERSION}

# Create required files for automake
touch AUTHORS ChangeLog NEWS README

# Apply patches
bash "$SCRIPT_DIR/apply-patches.sh" "$(pwd)" "$SCRIPT_DIR/patches"

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

# Repack source
cd ..
tar czf hplip-${VERSION}-patched.tar.gz hplip-${VERSION}/
rm -rf hplip-${VERSION}

# Update spec to use patched source
sed -i "s|hplip-%{version}.tar.gz|hplip-%{version}-patched.tar.gz|g" "$RPM_TOP/SPECS/hp-scanner-driver.spec"

# Update Release field with distro suffix
sed -i "s/Release:        1%{?dist}/Release:        1~${DISTRO_SUFFIX}%{?dist}/g" "$RPM_TOP/SPECS/hp-scanner-driver.spec"

# Build RPM
echo "Building .rpm package..."
cd "$RPM_TOP/SPECS"
rpmbuild -ba hp-scanner-driver.spec

# Copy output
echo "Copying packages to $OUTPUT_DIR..."
cp "$RPM_TOP/RPMS"/*/*.rpm "$OUTPUT_DIR/"
cp "$RPM_TOP/SRPMS"/*.src.rpm "$OUTPUT_DIR/" 2>/dev/null || true

write_md5sums_manifest

echo "=== Build Complete ==="
ls -lh "$OUTPUT_DIR"/*.rpm

# === TEST STEP: Install rpm inside container ===
echo ""
echo "=== TEST STEP: Installing .rpm inside container ==="
RPM_FILE=$(ls -t "$OUTPUT_DIR"/hp-scanner-driver-*.rpm 2>/dev/null | grep -v debuginfo | grep -v src | head -n1)
if [ -z "$RPM_FILE" ]; then
    echo "ERROR: No .rpm file found in $OUTPUT_DIR"
    exit 1
fi
echo "Installing: $RPM_FILE"

# Install dependencies based on distro
echo "Installing dependencies..."
if [ "$PKG_MANAGER" = "dnf" ]; then
    dnf install -y -q sane-backends-libs cups cups-libs 2>&1 | tee -a "$OUTPUT_DIR/install-dependencies-${DISTRO}.log" || true
elif [ "$PKG_MANAGER" = "zypper" ]; then
    # openSUSE zypper uses different flags than dnf
    # Note: libsane2 is called sane-backends on openSUSE
    zypper install -y --no-recommends cups cups-client sane-backends 2>&1 | tee -a "$OUTPUT_DIR/install-dependencies-${DISTRO}.log" || true
fi

# Install the package, capturing stdout and stderr to separate files
# Use --force to ignore missing proprietary plugin (libImageProcessor)
# This is expected - users need to run hp-plugin -i for some devices
rpm -ivh --force --nodeps "$RPM_FILE" > "$OUTPUT_DIR/install-stdout-${DISTRO}.log" 2> "$OUTPUT_DIR/install-stderr-${DISTRO}.log" || {
    EXIT_CODE=$?
    echo "rpm install failed with exit code $EXIT_CODE"
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
