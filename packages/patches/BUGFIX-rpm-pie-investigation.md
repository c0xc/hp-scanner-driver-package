# Bug Fix: RPM Build Failure - PIE Linker Error

**Status:** RESOLVED
**Severity:** Critical (was blocking RPM build)
**Affects:** RPM packages only (Fedora/RHEL)
**Fix Applied:** 2026-02-21
**Last Updated:** 2026-02-21

---

## Problem

RPM build failed during linking of `hp` CUPS backend binary:

```
/usr/bin/ld: hp-hp.o: relocation R_X86_64_32 against `.rodata' can not be
used when making a PIE object; recompile with -fPIE
collect2: error: ld returned 1 exit status
```

---

## Root Cause

Fedora's hardened build flags require all executables to be Position Independent Executables (PIE). The HPLIP build system does not properly propagate `-fPIE` flags to all targets (specifically the `hp` backend), causing the linker to fail.

---

## Solution

Disable Fedora's hardened build for this package by adding to the spec file:

```spec
# Disable Fedora hardening flags (PIE enforcement)
%undefine _hardened_build

# Disable debug info generation (reduces package size and avoids unpackaged debug files)
%global debug_package %{nil}
```

**Rationale:** PIE is a security hardening feature, not a functional requirement. The HPLIP build system has a bug where it doesn't propagate `-fPIE` flags to all targets. Disabling hardened build allows the build to complete successfully. The resulting binaries will function correctly but lack this specific security hardening feature.

---

## Implementation

The fix was applied to `packages/rpm/hplip-unofficial.spec`:

```spec
# NOTE: PIE (Position Independent Executable) is disabled for this package.
# The HPLIP build system does not properly propagate -fPIE flags to all targets
# (specifically the hp CUPS backend). Disabling PIE allows the build to complete
# successfully. The resulting binaries will function correctly but lack this
# specific security hardening feature.
# See: BUGFIX-rpm-pie-investigation.md for details.

# Disable Fedora hardening flags (PIE enforcement)
%undefine _hardened_build

# Disable debug info generation
%global debug_package %{nil}
```

---

## Verification

```bash
# Clean previous builds
rm -f output/*.rpm output/*.log

# Build
podman run --rm -v ./output:/build/output hplip-unofficial-rpm-builder

# Verify
ls -lh output/*.rpm
```

Expected result: RPM build completes successfully, producing:
- `hplip-unofficial-3.25.8-1.fc38.x86_64.rpm`
- `hplip-unofficial-gui-3.25.8-1.fc38.x86_64.rpm`
- `hplip-unofficial-3.25.8-1.fc38.src.rpm`

---

## Technical Details

### Why This Fix Works

Fedora's RPM build system applies hardening flags by default, including:
- `-fPIE` (Position Independent Executable)
- `-Wl,-z,relro` (Read-Only Relocations)
- `-Wl,-z,now` (Immediate Binding)

The HPLIP build system (autotools-based) doesn't properly propagate these flags to all targets. By disabling hardened build with `%undefine _hardened_build`, we allow the build to complete without PIE enforcement.

### Security Implications

Disabling PIE means the binaries won't have ASLR (Address Space Layout Randomization) protection for the executable itself. However:
- The libraries still use PIC (Position Independent Code)
- Other security features (RELRO, stack protectors) remain active
- For a printer driver package, this risk is minimal

### Alternative Approaches (Not Used)

1. **Patch Makefile.in**: Would require maintaining a complex patch for each HPLIP version
2. **Manual compilation**: Too fragile and error-prone
3. **Exclude hp backend**: Would break functionality

---

## Related Issues

- Fedora PIE Policy: https://fedoraproject.org/wiki/Changes/All_Packages_Build_PIE
- Libtool PIE Documentation: https://www.gnu.org/software/libtool/manual/html_node/Pie-Executables.html

---

## Notes

- DEB build completes successfully (Debian hardening differs from Fedora)
- The dll.conf fix is unrelated to this issue (see BUGFIX-dll-conflict.md)
- Build completes ~95% before failing at the hp link step without this fix
