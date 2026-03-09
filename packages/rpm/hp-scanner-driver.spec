# RPM spec file for hp-scanner-driver
# Maintainer: c0xc
# This is an unofficial package, not affiliated with or endorsed by HP.
#
# NOTE: PIE (Position Independent Executable) is disabled for this package.
# The HPLIP build system does not properly propagate -fPIE flags to all targets
# (specifically the hp CUPS backend). Disabling PIE allows the build to complete
# successfully. The resulting binaries will function correctly but lack this
# specific security hardening feature.
# See: BUGFIX-rpm-pie-investigation.md for details.
#

# Disable Fedora hardening flags (PIE enforcement)
%undefine _hardened_build

Name:           hp-scanner-driver
Version:        3.25.8
Release:        1%{?dist}
Summary:        HP scanner and printer drivers for modern Linux systems
License:        GPL-2.0-or-later AND LGPL-2.1-or-later
URL:            https://github.com/c0xc/hplip-packages
Source0:        hplip-%{version}-patched.tar.gz

BuildRequires:  gcc gcc-c++ make autoconf automake libtool pkg-config
BuildRequires:  cups-devel libusb-1_0-devel sane-backends-devel libjpeg-devel
BuildRequires:  libdbus-1-devel libavahi-devel libnet-snmp-devel
BuildRequires:  python3-devel python3-PyQt5-sip
BuildRequires:  rpm-build
Requires:       cups cups-client sane-backends python3-PyQt5-sip

%description
HPLIP is an integrated solution for HP inkjet and laser printers,
all-in-one devices, and scanners.

This package provides pre-built HP drivers with fixes for modern
Linux distributions. Unlike the official HP installer, this package
installs cleanly via dnf and can be removed cleanly.

Features:
- Printer drivers for HP inkjet and laser printers
- Scanner drivers for HP all-in-one devices
- HP Toolbox GUI for device management
- hp-setup wizard for easy printer setup
- hp-check diagnostics tool

This package is maintained independently and is not affiliated with or
endorsed by HP Development Company, L.P. HPLIP is a trademark of
HP Development Company, L.P.

%prep
%setup -q -n hplip-%{version}

%build
%configure \
    --disable-qt4 \
    --enable-qt5 \
    --disable-fax-build \
    --disable-static \
    --with-mimetype=application/vnd.hp-hpipl

make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}

# Remove dll.conf and dll.d - we manage them in post/preun (same fix as Debian)
# Upstream writes to /etc/sane.d/dll.conf which is owned by sane-backends-libs
rm -f %{buildroot}/etc/sane.d/dll.conf
rm -rf %{buildroot}/etc/sane.d/dll.d

# Create dll.d directory for %files section
mkdir -p %{buildroot}/etc/sane.d/dll.d

# Fix Python shebangs (rpmbuild complains about ambiguous #!/usr/bin/env python)
find %{buildroot} -type f \( -name "*.py" -o -name "pstotiff" \) -exec sed -i 's|^#!/usr/bin/env python$|#!/usr/bin/python3|; s|^#!/usr/bin/python$|#!/usr/bin/python3|' {} \;

%post
# Create drop-in config for SANE (modern approach, no conflict with sane-backends-libs)
mkdir -p /etc/sane.d/dll.d
echo "hpaio" > /etc/sane.d/dll.d/hpaio.conf
/sbin/ldconfig

%preun
if [ $1 -eq 0 ]; then
    # Remove drop-in config on uninstall
    rm -f /etc/sane.d/dll.d/hpaio.conf
    /sbin/ldconfig
fi

# Disable debug info generation (reduces package size and avoids unpackaged debug files)
%global debug_package %{nil}

%files
%dir /etc/sane.d/dll.d
%config(noreplace) /etc/hp/hplip.conf
%config(noreplace) /etc/udev/rules.d/56-hpmud.rules
%config(noreplace) /etc/xdg/autostart/hplip-systray.desktop
/usr/bin/
/usr/lib/cups/
/usr/lib/systemd/
/usr/lib64/*.so*
/usr/lib64/python3*/site-packages/*.so
/usr/lib64/sane/
/usr/share/cups/
/usr/share/doc/hplip-%{version}/
/usr/share/hal/
/usr/share/hplip/
/usr/share/ppd/HP/
%{_datadir}/applications/*.desktop

%changelog
* Fri Feb 20 2026 c0xc <c0xc@example.com> - 3.25.8-1
- Initial package by c0xc
- Custom build from HP's official HPLIP 3.25.8 sources
- Applied patches for Qt5 support and DESTDIR fix
- This is an unofficial package, not affiliated with HP
