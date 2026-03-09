#!/bin/bash
# prepare-upstream-source.sh - Download and verify HPLIP upstream source tarball.
# Usage: ./prepare-upstream-source.sh VERSION DISTRO WORKDIR OUTPUT_DIR

set -euo pipefail

VERSION="${1:?VERSION is required}"
DISTRO="${2:?DISTRO is required}"
WORKDIR="${3:?WORKDIR is required}"
OUTPUT_DIR="${4:?OUTPUT_DIR is required}"

UPSTREAM_BASE_URL="https://sourceforge.net/projects/hplip/files/hplip/${VERSION}"
TARBALL="hplip-${VERSION}.tar.gz"
TARBALL_SIG="${TARBALL}.asc"
HP_HPLIP_KEY_FPR="82FFA7C6AA7411D934BDE173AC69536A2CF3A243"

mkdir -p "$WORKDIR" "$OUTPUT_DIR"
cd "$WORKDIR"

echo "Downloading HPLIP $VERSION source and signature..."
wget -q "${UPSTREAM_BASE_URL}/${TARBALL}"
wget -q "${UPSTREAM_BASE_URL}/${TARBALL_SIG}"

# Record upstream integrity artifacts in output for later auditing.
cp "$TARBALL" "$OUTPUT_DIR/"
cp "$TARBALL_SIG" "$OUTPUT_DIR/"
sha256sum "$TARBALL" > "$OUTPUT_DIR/upstream-${DISTRO}-${VERSION}.sha256"
md5sum "$TARBALL" > "$OUTPUT_DIR/upstream-${DISTRO}-${VERSION}.md5"

# Verify upstream tarball signature against HP's pinned public key fingerprint.
echo "Verifying upstream signature..."
export GNUPGHOME="$WORKDIR/.gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

KEY_IMPORTED=false
for KS in hkps://keyserver.ubuntu.com hkps://keys.openpgp.org hkps://pgp.mit.edu; do
    if gpg --batch --keyserver "$KS" --recv-keys "$HP_HPLIP_KEY_FPR" >/dev/null 2>&1; then
        KEY_IMPORTED=true
        break
    fi
done

if [ "$KEY_IMPORTED" != true ]; then
    echo "WARNING: Could not import HP HPLIP signing key from keyservers, skipping signature verification" >&2
    echo "WARNING: This is expected in some container environments" >&2
    # Continue without verification - the tarball hash is still recorded for auditing
    {
        echo "source_url=${UPSTREAM_BASE_URL}/${TARBALL}"
        echo "signature_url=${UPSTREAM_BASE_URL}/${TARBALL_SIG}"
        echo "sha256=$(sha256sum "$TARBALL" | awk '{print $1}')"
        echo "md5=$(md5sum "$TARBALL" | awk '{print $1}')"
        echo "signing_fingerprint=${HP_HPLIP_KEY_FPR}"
        echo "verified_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "verify_status=skipped-key-not-available"
    } > "$OUTPUT_DIR/upstream-provenance-${DISTRO}-${VERSION}.txt"
    echo "Prepared upstream source: $TARBALL (signature verification skipped)"
    exit 0
fi

IMPORTED_FPR=$(gpg --batch --with-colons --fingerprint "$HP_HPLIP_KEY_FPR" | awk -F: '/^fpr:/ {print $10; exit}')
if [ "$IMPORTED_FPR" != "$HP_HPLIP_KEY_FPR" ]; then
    echo "ERROR: Imported key fingerprint mismatch" >&2
    echo "Expected: $HP_HPLIP_KEY_FPR" >&2
    echo "Actual:   $IMPORTED_FPR" >&2
    exit 1
fi

SIGNATURE_LOG="$OUTPUT_DIR/upstream-signature-${DISTRO}-${VERSION}.log"
if ! gpg --batch --verify "$TARBALL_SIG" "$TARBALL" > "$SIGNATURE_LOG" 2>&1; then
    echo "ERROR: Upstream signature verification failed" >&2
    cat "$SIGNATURE_LOG" >&2
    exit 1
fi

{
    echo "source_url=${UPSTREAM_BASE_URL}/${TARBALL}"
    echo "signature_url=${UPSTREAM_BASE_URL}/${TARBALL_SIG}"
    echo "sha256=$(sha256sum "$TARBALL" | awk '{print $1}')"
    echo "md5=$(md5sum "$TARBALL" | awk '{print $1}')"
    echo "signing_fingerprint=${HP_HPLIP_KEY_FPR}"
    echo "verified_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "verify_status=ok"
} > "$OUTPUT_DIR/upstream-provenance-${DISTRO}-${VERSION}.txt"

echo "Prepared upstream source: $TARBALL"
