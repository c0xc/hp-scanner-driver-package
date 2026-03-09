#!/bin/bash
# apply-patches.sh - Apply patches to HPLIP source
# Maintainer: c0xc
#
# Version-specific patch selection:
# - Patches named *-3.25.2.patch apply to HPLIP 3.25.2
# - Patches named *-3.25.8.patch apply to HPLIP 3.25.8
# - Patches without version suffix apply to all versions

set -e

SOURCE_DIR="$1"
PATCHES_DIR="$2"

if [ -z "$SOURCE_DIR" ] || [ -z "$PATCHES_DIR" ]; then
    echo "Usage: apply-patches.sh <source-dir> <patches-dir>"
    exit 1
fi

# Resolve to absolute paths BEFORE any cd
SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
PATCHES_DIR=$(cd "$PATCHES_DIR" && pwd)

# Detect HPLIP version from:
# 1. Directory name (e.g., hplip-3.25.8) - must check BEFORE cd
# 2. VERSION file in source
# 3. configure.in AC_INIT line
VERSION=""
SOURCE_BASENAME=$(basename "$SOURCE_DIR")
if [[ "$SOURCE_BASENAME" =~ hplip-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    VERSION="${BASH_REMATCH[1]}"
elif [ -f "$SOURCE_DIR/VERSION" ]; then
    VERSION=$(cat "$SOURCE_DIR/VERSION" 2>/dev/null | head -n1)
elif [ -f "$SOURCE_DIR/configure.in" ]; then
    VERSION=$(grep -oP 'AC_INIT\(\[hplip\],\s*\[\K[0-9.]+' "$SOURCE_DIR/configure.in" 2>/dev/null || true)
fi

echo "Detected HPLIP version: ${VERSION:-unknown}"

cd "$SOURCE_DIR"

# Apply patches from series file
if [ -f "$PATCHES_DIR/series" ]; then
    while IFS= read -r patch || [ -n "$patch" ]; do
        [ -z "$patch" ] && continue
        [[ "$patch" =~ ^# ]] && continue

        # The series file is authoritative and may intentionally pin a
        # versioned patch to a nearby upstream release when it still applies.
        if [ -f "$PATCHES_DIR/$patch" ]; then
            echo "  Applying: $patch"
            patch -p1 < "$PATCHES_DIR/$patch"
        fi
    done < "$PATCHES_DIR/series"
else
    # Apply all .patch files in order
    for patch in "$PATCHES_DIR"/*.patch; do
        [ -f "$patch" ] || continue
        echo "  Applying: ${patch##*/}"
        patch -p1 < "$patch"
    done
fi
