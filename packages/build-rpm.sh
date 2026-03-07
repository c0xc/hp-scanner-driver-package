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
mkdir -p ~/rpmbuild/SOURCES
mkdir -p ~/rpmbuild/SPECS
mkdir -p ~/rpmbuild/BUILD
mkdir -p ~/rpmbuild/RPMS
mkdir -p ~/rpmbuild/SRPMS
mkdir -p "$WORKDIR"

cd "$WORKDIR"

# Download source
echo "Downloading HPLIP $VERSION source..."
wget -q "https://sourceforge.net/projects/hplip/files/hplip/${VERSION}/hplip-${VERSION}.tar.gz"
cp hplip-${VERSION}.tar.gz ~/rpmbuild/SOURCES/

# Copy and update spec file
cp "$SCRIPT_DIR/rpm/hp-scanner-driver.spec" ~/rpmbuild/SPECS/
sed -i "s/Version:        3.25.8/Version:        ${VERSION}/g" ~/rpmbuild/SPECS/hp-scanner-driver.spec

# Prepare source with patches
echo "Preparing source with patches..."
cd ~/rpmbuild/SOURCES
tar xzf hplip-${VERSION}.tar.gz
cd hplip-${VERSION}

# Create required files for automake
touch AUTHORS ChangeLog NEWS README

# Apply patches
bash "$SCRIPT_DIR/apply-patches.sh" "$(pwd)" "$SCRIPT_DIR/patches"

# Repack source
cd ..
tar czf hplip-${VERSION}-patched.tar.gz hplip-${VERSION}/
rm -rf hplip-${VERSION}

# Update spec to use patched source
sed -i "s|hplip-%{version}.tar.gz|hplip-%{version}-patched.tar.gz|g" ~/rpmbuild/SPECS/hp-scanner-driver.spec

# Update Release field with distro suffix
sed -i "s/Release:        1%{?dist}/Release:        1~${DISTRO_SUFFIX}%{?dist}/g" ~/rpmbuild/SPECS/hp-scanner-driver.spec

# Build RPM
echo "Building .rpm package..."
cd ~/rpmbuild/SPECS
rpmbuild -ba hp-scanner-driver.spec

# Copy output
echo "Copying packages to $OUTPUT_DIR..."
cp ~/rpmbuild/RPMS/*/*.rpm "$OUTPUT_DIR/"
cp ~/rpmbuild/SRPMS/*.src.rpm "$OUTPUT_DIR/" 2>/dev/null || true

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
    zypper install -y -q sane-backends-libs cups cups-libs 2>&1 | tee -a "$OUTPUT_DIR/install-dependencies-${DISTRO}.log" || true
fi

# Install the package, capturing stdout and stderr to separate files
rpm -ivh "$RPM_FILE" > "$OUTPUT_DIR/install-stdout-${DISTRO}.log" 2> "$OUTPUT_DIR/install-stderr-${DISTRO}.log" || {
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
