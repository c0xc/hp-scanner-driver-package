# Bug Fix: /etc/sane.d/dll.conf File Conflict

**Status:** RESOLVED  
**Severity:** Critical (blocks installation)  
**Affects:** DEB and RPM packages

---

## Problem

Installation fails with file conflict error:

**Debian/Ubuntu:**
```
dpkg: error: trying to overwrite '/etc/sane.d/dll.conf', 
which is also in package libsane-common
```

**Fedora/RHEL:**
```
file /etc/sane.d/dll.conf conflicts between attempted installs of 
hplip-unofficial and sane-backends-libs
```

---

## Root Cause

Upstream HPLIP writes directly to `/etc/sane.d/dll.conf` during `make install`. This file is owned by system SANE packages (`libsane-common` or `sane-backends-libs`), causing package manager conflicts.

---

## Solution

Use SANE's drop-in configuration directory (`/etc/sane.d/dll.d/`) instead of modifying the shared `dll.conf` file.

### Implementation Summary

| Component | Action |
|-----------|--------|
| Build (`rules`/`spec`) | Remove `dll.conf` and `dll.d/` from package |
| Install (`postinst`/`%post`) | Create `/etc/sane.d/dll.d/hpaio.conf` with content `hpaio` |
| Uninstall (`prerm`/`%preun`) | Remove `/etc/sane.d/dll.d/hpaio.conf` |

### Files Modified

- `packages/debian/rules`
- `packages/debian/postinst`
- `packages/debian/prerm`
- `packages/rpm/hplip-unofficial.spec`
- `packages/build-deb.sh` (test step)
- `packages/build-rpm.sh` (test step)

---

## Verification

```bash
# After installation, verify:
ls -la /etc/sane.d/dll.d/hpaio.conf
cat /etc/sane.d/dll.d/hpaio.conf
# Output should be: hpaio

# Original file unchanged
head /etc/sane.d/dll.conf
```

---

## Detailed Technical Information

### Why This Approach

1. **No File Conflicts**: Each package manages its own file in `dll.d/`
2. **SANE Compatible**: Modern SANE reads both `dll.conf` and `dll.d/*.conf`
3. **Clean Uninstall**: Drop-in file removed when package is removed
4. **Persistent Fix**: Applied automatically for all future HPLIP versions

### Debian Implementation

**debian/rules:**
```make
override_dh_auto_install:
	dh_auto_install -- DESTDIR=$(CURDIR)/debian/hplip-unofficial
	rm -f $(CURDIR)/debian/hplip-unofficial/etc/sane.d/dll.conf
	rm -rf $(CURDIR)/debian/hplip-unofficial/etc/sane.d/dll.d
```

**debian/postinst:**
```bash
#!/bin/bash
set -e

case "$1" in
    configure)
        mkdir -p /etc/sane.d/dll.d
        echo "hpaio" > /etc/sane.d/dll.d/hpaio.conf
        /sbin/ldconfig
        ;;
esac

exit 0
```

**debian/prerm:**
```bash
#!/bin/bash
set -e

case "$1" in
    remove|deconfigure)
        rm -f /etc/sane.d/dll.d/hpaio.conf
        ;;
esac

exit 0
```

### RPM Implementation

**hplip-unofficial.spec:**
```spec
%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}
rm -f %{buildroot}/etc/sane.d/dll.conf
rm -rf %{buildroot}/etc/sane.d/dll.d

%post
mkdir -p /etc/sane.d/dll.d
echo "hpaio" > /etc/sane.d/dll.d/hpaio.conf
/sbin/ldconfig

%preun
if [ $1 -eq 0 ]; then
    rm -f /etc/sane.d/dll.d/hpaio.conf
    /sbin/ldconfig
fi

%files
%dir /etc/sane.d/dll.d
```

### Test Results

**DEB Build:**
```bash
$ podman run --rm -v ./output:/build/output hplip-unofficial-deb-builder
# Result: SUCCESS
# Output: hplip-unofficial_3.25.8-1_amd64.deb
# Install test: PASSED (install-stderr.log is empty)
```

**RPM Build:**
```bash
$ podman run --rm -v ./output:/build/output hplip-unofficial-rpm-builder
# Result: INCOMPLETE (separate PIE issue - see BUGFIX-rpm-pie-investigation.md)
```

---

## References

- SANE Backend Configuration: https://sane-project.alioth.debian.org/
- Debian Policy - Configuration Files: https://www.debian.org/doc/debian-policy/ch-files.html
- RPM Packaging Guide: https://rpm-packaging-guide.github.io/
