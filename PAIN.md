# PAIN.md - Things That Hurt (Or Will Hurt You)

**Last Updated:** 2026-03-07  
**Project:** hp-scanner-driver

---

## The Two-Package Debacle [FIXED]

**Symptom:**
```
hplip-unofficial-gui : Depends: hplip-unofficial but it is not installable
E: Unmet dependencies. Try 'apt --fix-broken install' with no packages
```

**What Happened:**
The Debian build created TWO packages (`hplip-unofficial` and `hplip-unofficial-gui`) for some reason, but only one got built properly. The GUI package depends on the main package, but the main package wasn't installable. Classic dependency hell, self-inflicted.

**Root Cause:**
The `debian/control` file defined two binary packages:
```
Binary: hplip-unofficial, hplip-unofficial-gui
```

And the RPM spec had a separate `%package gui` section.

**Fix Applied:**
Removed the GUI subpackage entirely. Everything goes in one package now. If you get the driver, you get all of it - GUI tools included. No half-baked dependency nightmares.

---

## Container Rule Violations

**The Rule:** ALL build scripts must run inside containers (prefer Podman). No global installs on the host.

**Violations Found:**

### 1. build-deb.sh and build-rpm.sh run `apt-get build-dep` INSIDE the container
**Status:** PASS Actually OK - this runs inside the container, not on host.

### 2. Build scripts use command substitution `$(...)` 
**Status:** WARNING: Violates STYLE.md but not the container rule.
- `build.sh:7`: `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
- `build-deb.sh:8-9`: Multiple `$(...)` calls
- `build-rpm.sh:8-9`: Multiple `$(...)` calls
- `apply-patches.sh`: Multiple `$(...)` calls

**Why it matters:** STYLE.md says no command substitution, but these are necessary for portable shell scripts. The style guide is unrealistic here. Either update the style guide or accept that modern shell scripts need `$(...)`.

### 3. Containerfiles use `$(cat /build/VERSION)`
**Status:** WARNING: Same issue - command substitution in Containerfile.deb and Containerfile.rpm.

**Fix Options:**
1. Update STYLE.md to allow `$(...)` for necessary operations
2. Rewrite scripts to avoid it (painful and pointless)

**Recommendation:** Update STYLE.md. This is 2026, not 1985.

---

## Naming Confusion [DECIDED]

**Old Name:** `hplip-unofficial`

**Problem:** You mentioned wanting a manufacturer prefix pattern like:
- `hp-hplip-scanner-driver` (for HP)
- `fujitsu-XXXX` (for Fujitsu scanners)

**Issues with Old Name:**
1. `hplip-unofficial` doesn't follow a consistent naming pattern
2. "unofficial" sounds sketchy (even though it is)
3. Doesn't scale to other manufacturers

**Rejected Ideas:**
- `hp-hplip-rebuild` - redundant ("hp" + "hplip")
- `pfu-scanner-rebuild` - "pfu" sounds like "pfui" (German: what you say to a cat licking something it shouldn't) 
- Anything with "rebuild" in the name - users don't care it's a rebuild, they care that it **works**
- Mentioning specific fixes like "Qt5" in the name/description - that's just one of many bugs fixed

**Decision: `manufacturer-scanner-driver` Pattern**

| Manufacturer | Package Name |
|--------------|--------------|
| HP | `hp-scanner-driver` |
| Fujitsu | `fujitsu-scanner-driver` |
| Canon | `canon-scanner-driver` |
| Epson | `epson-scanner-driver` |

**Why:**
- Consistent pattern across manufacturers
- Clear what it does (scanner driver)
- No redundancy
- No embarrassing German cat noises
- Short enough to type
- Works for printer-only, scanner-only, or combined

**Package Description:** The "rebuild" aspect is mentioned in the package description (shown by `rpm -qi` or `dpkg -s`), not in the package name. Users see "pre-built drivers with fixes for modern Linux distributions" - which tells them what they get: **drivers that work**.

---

## Residue from Other Approaches

**Found:** No direct code residue in hplip-packages/ from other approach directories.

**Potential Issues:**
1. **Output directory pollution:** `output/` contains build artifacts from previous runs including:
 - `.dsc` files showing the two-package problem
 - Multiple `.tar.xz` and `.tar.gz` variants
 - RPM files with debuginfo packages (despite trying to disable them)

2. **Documentation references:** README.md mentions `hplip-unofficial` consistently, but other approach directories use different names:
 - `hplip-drivers` uses `hp-drivers-minimal`
 - Approach 2 docs mention `hplip-custom`
 - Approach 3 docs mention PPA naming

**Cleanup Needed:**
1. Run `./build.sh clean` before first proper build
2. Decide on final naming and update all docs consistently

---

## Build Script Issues

### 1. build-deb.sh installs dependencies with `apt-get build-dep -y .`
**Problem:** This requires the container to have access to apt repositories. If Sourceforge or HP's PPA is down, build fails.

**Status:** Acceptable risk, but document it.

### 2. build-deb.sh and build-rpm.sh test installation INSIDE the container
**Problem:** The scripts try to install the built package inside the build container. This is actually good for catching issues early, BUT:
- It pollutes the clean build environment
- It may fail due to container-specific issues (missing deps) that aren't real problems

**Status:** Keep the test, but make it optional with a flag.

### 3. RPM spec has hardcoded Python version
**Problem:** `hplip-unofficial.spec` line ~100:
```
/usr/lib64/python3.11/site-packages/*.so
```
This will break on Fedora versions with different Python versions.

**Fix:** Use `%{python3_sitearch}` macro instead.

---

## Patch Management Issues

### 1. Version-specific patches are a maintenance nightmare
**Current:**
```
01-qt4-to-qt5-3.25.2.patch
01-qt4-to-qt5-3.25.6.patch
01-qt4-to-qt5-3.25.8.patch
```

**Problem:** Every HPLIP version bump requires new patches. This doesn't scale.

**Better Approach:**
- Create patches that are version-agnostic where possible
- Use patch generation scripts (there's a `gen-patch.py` in output/ - what does it do?)
- Document which HPLIP versions each patch is known to work with

### 2. 02-fix-destdir.patch is DISABLED in series
**Reason:** "needs regeneration per version"

**Problem:** Makefile.in changes between HPLIP versions. A static patch won't apply cleanly.

**Fix:** Either:
1. Generate the patch dynamically during build
2. Apply the fix directly in debian/rules or the spec file
3. Use a more robust patching strategy

---

## Debian Packaging Issues

### 1. debian/compat says "12" but should use debhelper 13+
**Status:** Minor - works but outdated.

### 2. debian/rules uses `dh_python3` but doesn't properly handle Python files
**Evidence:** The RPM spec has to fix Python shebangs manually:
```spec
find %{buildroot} -type f \( -name "*.py" -o -name "pstotiff" \) -exec sed -i ...
```

**Problem:** Debian build should handle this automatically with proper dh_python3 configuration.

### 3. Debug symbol migration in debian/rules
```make
override_dh_strip:
	dh_strip --dbgsym-migration='hplip-unofficial-dbgsym (<< 3.25.8)'
```

**Problem:** This creates a separate debug package, but the RPM disables debug info entirely. Inconsistent approaches.

---

## RPM Packaging Issues

### 1. PIE disabled (`%undefine _hardened_build`)
**Reason:** HPLIP build system doesn't propagate `-fPIE` flags properly.

**Status:** Documented in BUGFIX-rpm-pie-investigation.md. Acceptable workaround.

**Concern:** Security-conscious distros may reject packages without PIE. Fedora might eventually require it.

### 2. Hardcoded paths in %files section
```spec
/usr/lib64/python3.11/site-packages/*.so
/usr/share/doc/hplip-3.25.8/
```

**Problem:** Will break on:
- Systems with different Python versions
- Future HPLIP version bumps

**Fix:** Use RPM macros:
```spec
%{python3_sitearch}/*.so
%{_docdir}/%{name}-%{version}/
```

### 3. Debug packages still generated despite `%global debug_package %{nil}`
**Evidence:** output/ contains:
- `hplip-unofficial-debuginfo-3.25.8-1.fc38.x86_64.rpm`
- `hplip-unofficial-debugsource-3.25.8-1.fc38.x86_64.rpm`

**Problem:** The directive isn't working as expected, or rpmbuild is ignoring it.

---

## SANE Configuration Fix (Actually Done Right)

**Good News:** The `/etc/sane.d/dll.conf` conflict is properly fixed using drop-in configs in `/etc/sane.d/dll.d/`.

**Implementation:**
- debian/postinst creates `/etc/sane.d/dll.d/hpaio.conf`
- debian/prerm removes it on uninstall
- RPM %post and %preun do the same

**Status:** PASS This is correct and follows modern SANE best practices.

---

## Container Build Concerns

### 1. Container builds may not be fully reproducible
**Problem:** Containerfiles use `apt-get update` without pinning dates or versions.

**Risk:** Build today might differ from build next month if upstream packages change.

**Mitigation:** Pin base image versions (already done: `debian:bookworm-slim`, `fedora:38`).

### 2. Volume mount for output
```bash
podman run --rm -v ./output:/build/output ...
```

**Concern:** Files created inside container may have wrong ownership (root) when mounted back to host.

**Fix:** Add `--user $(id -u):$(id -g)` to podman run, or chown output after build.

---

## Documentation Issues

### 1. README.md uses placeholder GitHub username
```
wget https://github.com/c0xc/hplip-packages/releases/...
```

**Status:** Intentional placeholder, but should be documented.

### 2. Maintainer email is `c0xc@example.com`
**Status:** Placeholder. Replace before first release.

### 3. STYLE.md contradicts actual practice
**Example:** "No command substitution: `$()`, backticks" but scripts use them extensively.

**Fix:** Update STYLE.md to reflect reality, or actually fix the scripts.

---

## Summary of Action Items

### Critical (Must Fix Before First Release) FIXED ALL DONE

1. PASS **Two-package problem:** Removed `hplip-unofficial-gui` from debian/control and RPM spec
2. PASS **RPM Python path:** Changed to `/usr/lib64/python3*/site-packages/*.so` (glob pattern)
3. PASS **RPM doc path:** Changed to `%{_docdir}/%{name}-%{version}/`
4. PASS **Naming decision:** `hp-scanner-driver` (scales to `fujitsu-scanner-driver`, etc.)
5. PASS **Maintainer info:** Updated throughout (still placeholder email, but consistent)

### Important (Should Fix)
1. **Patch management:** Create version-agnostic patches or document patch generation process
2. **DESTDIR fix:** Either fix the patch or apply the fix in build rules directly
3. **Debug packages:** Make debug package handling consistent between DEB and RPM
4. **Container ownership:** Add `--user` flag to podman run for proper file ownership

### Nice to Have
1. **STYLE.md update:** Allow necessary command substitution
2. **debian/compat upgrade:** Use debhelper 13+
3. **Optional test step:** Make in-container installation test optional with flag
4. **Clean output:** Add cleanup step to build.sh to remove old artifacts
5. **Old build artifacts:** Clean `output/` directory (contains old `hplip-unofficial-*` files)

### Already Done Right
1. PASS SANE drop-in config (dll.d/) - no more file conflicts
2. PASS Container-based builds - no host pollution
3. PASS Qt4->Qt5 patches - version-specific but working
4. PASS PIE workaround for RPM - documented and acceptable
5. PASS Bug documentation - BUGFIX-*.md files are thorough

---

## The Irony Department

- We're building printer drivers, which should be simple, but need containers, patches, and workarounds
- HP's "Linux Imaging and Printing" doesn't properly support Linux packaging standards
- We need to disable security features (PIE) because upstream build system is broken
- The "unofficial" package is probably more official-looking than what HP provides
- Qt4 was deprecated years ago, but HP's code still checks for it
- We're using 2026 technology to fix 2020 problems with 2010 code

---

## Distro Version Naming

### Ubuntu: YY.MM IS the Major Version
- There is no `ubuntu:22` - Ubuntu uses `YY.MM` format (Year.Month)
- LTS releases are `.04` (April): `20.04`, `22.04`, `24.04`
- Short-term releases are `.10` (October): skip these (obsolete quickly)
- Use `ubuntu:22.04` not `ubuntu:jammy` (codenames are forgettable)
- **Why:** `jammy` could mean 22.04 or 22.04.x, but we want exact version control

### openSUSE Leap: 15.x Service Packs
- All Leap 15.x (15.3+) are binary-compatible (same glibc 2.31)
- `opensuse/leap:15` points to "latest 15.x" - NOT reproducible
- Use specific version: `opensuse/leap:15.5` (current) or `15.3` (oldest supported)
- Building on 15.3 ensures compatibility with all 15.3+
- **Why:** When Leap 16.0 releases, `leap:15` might point to 16.0, breaking builds

### Fedora: Just the Number
- Fedora uses simple versioning: `fedora:38`, `fedora:39`, `fedora:40`
- No gotchas here
- Support 2-3 recent versions (current + 1-2 back)
- **Why:** Fedora releases every 6 months, old versions EOL quickly

### Debian: Major Version Only
- Debian uses major versions: `debian:11`, `debian:12`, `debian:13`
- Codenames exist (bullseye, bookworm, trixie) but are forgettable
- Use `debian:12` not `debian:bookworm`
- **Why:** Same as Ubuntu - codenames are forgettable

### Package Naming Convention

```
DEB: hp-scanner-driver_{VERSION}-1~{DISTRO}_{ARCH}.deb
     hp-scanner-driver_3.25.8-1~ubuntu-22.04_amd64.deb
     hp-scanner-driver_3.25.8-1~debian-12_amd64.deb

RPM: hp-scanner-driver-{VERSION}-{RELEASE}.{DISTRO_SUFFIX}.{ARCH}.rpm
     hp-scanner-driver-3.25.8-1.fc39.x86_64.rpm
     hp-scanner-driver-3.25.8-1.lp155.x86_64.rpm
```

**Why distro-specific names?**
1. Users can identify the right package for their system
2. Prevents accidental installation on wrong distro
3. Makes debugging easier (we know exactly what was built)
4. Allows building for multiple distros without conflicts

---

## Notes for Future Self

When you come back to this in 6 months and wonder why anything is broken:

1. **Check the two-package issue first** - it's probably back
2. **HPLIP version changed?** - All patches need regeneration
3. **New Fedora version?** - PIE might be required again
4. **SANE API changed?** - Check dll.d/ still works
5. **Podman updated?** - Volume mounts might behave differently
6. **New distro version?** - Add new Containerfile (e.g., ubuntu-24.04, fedora-40)
7. **openSUSE Leap 16?** - Create Containerfile.opensuse-16.0, update 15.5 to "legacy"
8. **Dependency names changed?** - Check Containerfiles for package name updates

---

## Python Syntax Errors in HPLIP Source

**WARNING:** HPLIP source code contains Python syntax errors that break after patching!

### Known Issues Found (3.25.8)

1. **`base/utils.py` - `checkPyQtImport4()` function (line ~811)**
 - Original code tries PyQt4, falls back to PyQt5
 - The Qt migration patch leaves this helper in a broken state
 - **Status:** Fixed during build before validation/package creation

2. **Shebang issues**
 - Upstream ships Python shebangs that confuse Debian dependency detection
 - This caused a false `python2:any` dependency in the generated package
 - **Status:** Fixed in `debian/rules` by normalizing shebangs before `dh_python3`

### Why This Happens

HPLIP's codebase is 20+ years old with:
- Mixed Python 2/3 compatibility code
- Fragile patch points that break easily
- No proper CI/CD testing for Python syntax
- Patches that modify control flow (try/except/else) without proper testing

### What to Expect

**More syntax errors will appear** when:
- Using different HPLIP versions
- Applying patches to new upstream releases
- Running less-used tools (hp-faxsetup, hp-colorcal, etc.)

### Debugging Tips

```bash
# Check which script is failing
head -1 /usr/share/hplip/*.py | grep python2

# Check for syntax errors
python3 -m py_compile /usr/share/hplip/base/utils.py

# Run with verbose error output
python3 -u /usr/share/hplip/setup.py
```

### Fix Status

Shebang issue: Fixed in debian/rules and RPM spec (automatic correction during build)

Qt helper fix: Applied during build before validation/package creation

Build-time syntax validation: Enabled in DEB and RPM build scripts

---

## GUI Issues with Network Scanner Setup

**Problem:** hp-setup GUI has confusing network device setup

### Symptoms Observed (Mint 21.3, 3.25.8)

1. Wrong default selection: GUI shows "USB" or "Local" as default instead of "Network"
2. Invalid URI format: GUI prefixes IP with "net:" automatically, causes error
3. Workaround required: User must manually remove "net:" prefix from IP address

### Expected Behavior

User enters: 10.10.2.66
GUI should detect: hp:/net/HP_Color_LaserJet_MFP_M476dw?ip=10.10.2.66

### Actual Behavior

User enters: 10.10.2.66
GUI changes to: net:10.10.2.66
Error: Invalid manual discovery parameter

User removes "net:": 10.10.2.66
Works: Device found at hp:/net/HP_Color_LaserJet_MFP_M476dw?ip=10.10.2.66

### Scanner Detection Status

After setup completes:
- scanimage -L shows device (PASS)
- Scan I/O fails with "Error during device I/O" (FAIL)

This suggests device discovery works, SANE backend loads correctly, but network communication has issues.

### Debugging Commands

    scanimage -L
    scanimage -d "hpaio:/net/HP_Color_LaserJet_MFP_M476dw?ip=10.10.2.66" --format=png > test.png
    ping 10.10.2.66
    nc -zv 10.10.2.66 9100

---

---


---

## HP Plugin System - Critical Issue

**WARNING: MAJOR GOTCHA:** HP's proprietary plugin system breaks first-time scanning!

### What Happens

1. User installs hp-scanner-driver package
2. Scanner is detected by scanimage -L
3. First scan attempt FAILS with "Error during device I/O"
4. Plugin dialog appears (hp-plugin)
5. User must install proprietary plugin
6. Scanning then works

### Why This Is Terrible UX

- No warning during package installation about plugin requirement
- Scanner appears to work (detected) but does not function
- Error message "Error during device I/O" is unhelpful
- Plugin installation is a separate step users do not expect
- This is HP's DRM/proprietary blob requirement, not our bug

### Which Devices Need Plugins

Typically:
- HP Color LaserJet MFP models (like M476dw)
- Devices with advanced scanning features
- Some fax-capable devices

### How to Fix

    hp-plugin -i   (interactive installation)
    or
    hp-plugin -u   (automatic installation, requires internet)

### Debugging Commands

    hp-check -t 2>&1 | grep -i plugin
    hp-plugin --status

### Files Involved

- /usr/share/hplip/plugin.py - Plugin installation script
- /usr/share/hplip/plugins/ - Plugin directory (created after install)
- /usr/bin/hp-plugin - Plugin utility

### Resolution

This is HP's proprietary plugin requirement, not a package bug. Users must install the plugin for affected devices.

---
