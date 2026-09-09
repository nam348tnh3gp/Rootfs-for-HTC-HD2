#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Debian 7 Wheezy ARMEL rootfs builder
#
# Target:
#   HTC HD2 / HTC Leo
#
# Architecture:
#   ARMEL (32-bit ARM, soft-float)
#
# Distribution:
#   Debian GNU/Linux 7 Wheezy
#
# Root device:
#   /dev/mmcblk0p2
#
# Existing boot files are NOT modified:
#   startup.txt
#   zImage
#   initrd.gz
###############################################################################

###############################################################################
# Paths
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Script:
#   <repo>/scripts/build-wheezy-armel.sh
#
# Project root:
#   <repo>
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="$PROJECT_DIR/output"
ROOTFS="$OUTPUT_DIR/rootfs"

###############################################################################
# Debian configuration
###############################################################################

ARCH="armel"
SUITE="wheezy"

# Debian Wheezy is EOL and archived.
MIRROR="http://archive.debian.org/debian"

###############################################################################
# Environment
###############################################################################

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

###############################################################################
# Root check
###############################################################################

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    echo
    echo "Run:"
    echo
    echo "    sudo scripts/build-wheezy-armel.sh"
    echo
    exit 1
fi

###############################################################################
# Required commands
###############################################################################

echo "==> Checking required commands"

REQUIRED_COMMANDS=(
    debootstrap
    mount
    umount
    mountpoint
    chroot
    tar
)

for command in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command"
        exit 1
    fi
done

###############################################################################
# QEMU check
###############################################################################

echo "==> Checking QEMU ARM emulator"

if [ ! -x /usr/bin/qemu-arm-static ]; then
    echo "ERROR: /usr/bin/qemu-arm-static not found."
    echo
    echo "Install qemu-user-static first."
    exit 1
fi

###############################################################################
# Cleanup function
###############################################################################

cleanup() {
    set +e

    echo
    echo "==> Cleaning up mounts"

    if mountpoint -q "$ROOTFS/run"; then
        umount -lf "$ROOTFS/run"
    fi

    if mountpoint -q "$ROOTFS/sys"; then
        umount -lf "$ROOTFS/sys"
    fi

    if mountpoint -q "$ROOTFS/proc"; then
        umount -lf "$ROOTFS/proc"
    fi

    if mountpoint -q "$ROOTFS/dev"; then
        umount -lf "$ROOTFS/dev"
    fi
}

trap cleanup EXIT

###############################################################################
# Prepare output directory
###############################################################################

echo "==> Preparing output directory"

rm -rf "$OUTPUT_DIR"

mkdir -p "$ROOTFS"

###############################################################################
# Bootstrap Debian Wheezy ARMEL
###############################################################################

echo
echo "============================================================"
echo " Debian Wheezy ARMEL bootstrap"
echo "============================================================"
echo
echo "Architecture : $ARCH"
echo "Suite        : $SUITE"
echo "Mirror       : $MIRROR"
echo "Rootfs       : $ROOTFS"
echo

debootstrap \
    --arch="$ARCH" \
    --foreign \
    --no-check-gpg \
    "$SUITE" \
    "$ROOTFS" \
    "$MIRROR"

###############################################################################
# Install QEMU into rootfs
###############################################################################

echo
echo "==> Installing QEMU ARM emulator into rootfs"

cp \
    /usr/bin/qemu-arm-static \
    "$ROOTFS/usr/bin/qemu-arm-static"

###############################################################################
# Configure APT for Debian Archive
###############################################################################

echo "==> Configuring Debian Wheezy archive"

mkdir -p "$ROOTFS/etc/apt/apt.conf.d"

cat > "$ROOTFS/etc/apt/sources.list" <<'EOF'
deb [trusted=yes] http://archive.debian.org/debian wheezy main
deb [trusted=yes] http://archive.debian.org/debian-security wheezy/updates main
EOF

cat > "$ROOTFS/etc/apt/apt.conf.d/99archive" <<'EOF'
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
APT::Get::AllowUnauthenticated "true";
EOF

###############################################################################
# Temporary DNS
###############################################################################

echo "==> Configuring temporary DNS"

cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

###############################################################################
# Mount virtual filesystems
###############################################################################

echo "==> Mounting /dev"

mount --bind /dev "$ROOTFS/dev"

echo "==> Mounting /proc"

mount -t proc proc "$ROOTFS/proc"

echo "==> Mounting /sys"

mount -t sysfs sysfs "$ROOTFS/sys"

echo "==> Mounting /run"

mkdir -p "$ROOTFS/run"

mount --bind /run "$ROOTFS/run"

###############################################################################
# Debian second stage
###############################################################################

echo
echo "==> Running debootstrap second stage"

chroot "$ROOTFS" \
    /debootstrap/debootstrap \
    --second-stage

###############################################################################
# Prevent services from starting inside chroot
###############################################################################

echo "==> Creating policy-rc.d"

cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF

chmod +x "$ROOTFS/usr/sbin/policy-rc.d"

###############################################################################
# Hostname
###############################################################################

echo "==> Configuring hostname"

echo "htc-hd2" > "$ROOTFS/etc/hostname"

###############################################################################
# Hosts
###############################################################################

echo "==> Configuring hosts"

cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1       localhost
127.0.1.1       htc-hd2

::1             localhost ip6-localhost ip6-loopback
EOF

###############################################################################
# fstab
###############################################################################

echo "==> Configuring fstab"

cat > "$ROOTFS/etc/fstab" <<'EOF'
/dev/mmcblk0p2  /      auto  defaults,noatime  0 1
proc            /proc  proc  defaults          0 0
sysfs           /sys   sysfs defaults          0 0
tmpfs           /tmp   tmpfs defaults          0 0
EOF

###############################################################################
# Network
###############################################################################

echo "==> Configuring network"

mkdir -p "$ROOTFS/etc/network"

cat > "$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback
EOF

###############################################################################
# Install minimal userspace
###############################################################################

echo
echo "============================================================"
echo " Installing minimal userspace"
echo "============================================================"
echo

chroot "$ROOTFS" /bin/bash <<'CHROOT'

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

###############################################################################
# APT update
###############################################################################

echo "==> Updating package lists"

apt-get \
    -o Acquire::Check-Valid-Until=false \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    -o APT::Get::AllowUnauthenticated=true \
    update

###############################################################################
# Install packages
###############################################################################

echo "==> Installing packages"

apt-get \
    -o Acquire::Check-Valid-Until=false \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    -o APT::Get::AllowUnauthenticated=true \
    install -y \
    --allow-unauthenticated \
    --no-install-recommends \
    sysvinit \
    sysvinit-utils \
    udev \
    kmod \
    module-init-tools \
    procps \
    net-tools \
    ifupdown \
    iproute \
    iputils-ping \
    less \
    nano \
    ca-certificates

CHROOT

###############################################################################
# Verify init
###############################################################################

echo "==> Verifying /sbin/init"

if [ ! -x "$ROOTFS/sbin/init" ]; then
    echo "ERROR: /sbin/init was not created."
    exit 1
fi

echo "==> /sbin/init:"
ls -l "$ROOTFS/sbin/init"

###############################################################################
# Remove QEMU from final rootfs
###############################################################################

echo "==> Removing QEMU from final rootfs"

rm -f "$ROOTFS/usr/bin/qemu-arm-static"

###############################################################################
# Remove policy-rc.d
###############################################################################

echo "==> Removing temporary policy-rc.d"

rm -f "$ROOTFS/usr/sbin/policy-rc.d"

###############################################################################
# Clean APT cache
###############################################################################

echo "==> Cleaning APT cache"

rm -rf "$ROOTFS/var/cache/apt/"*
rm -rf "$ROOTFS/var/lib/apt/lists/"*

###############################################################################
# Clean temporary files
###############################################################################

echo "==> Cleaning temporary files"

rm -rf "$ROOTFS/tmp/"*
rm -rf "$ROOTFS/var/tmp/"*

###############################################################################
# Fix temporary directory permissions
###############################################################################

chmod 1777 "$ROOTFS/tmp"

###############################################################################
# Remove temporary DNS configuration
###############################################################################

echo "==> Removing temporary DNS configuration"

rm -f "$ROOTFS/etc/resolv.conf"

###############################################################################
# Build information
###############################################################################

echo "==> Writing build information"

cat > "$ROOTFS/etc/htc-hd2-build-info" <<'EOF'
Target: HTC HD2
Codename: htc-leo
Distribution: Debian GNU/Linux 7 Wheezy
Architecture: armel
Root device: /dev/mmcblk0p2
Init: /sbin/init
Boot files: existing startup.txt, zImage and initrd.gz
Rootfs builder: GitHub Actions
EOF

###############################################################################
# Verify Debian architecture
###############################################################################

echo "==> Verifying Debian architecture"

if [ -f "$ROOTFS/var/lib/dpkg/arch" ]; then
    echo "dpkg architecture information:"
    cat "$ROOTFS/var/lib/dpkg/arch"
fi

###############################################################################
# Final cleanup
###############################################################################

echo
echo "============================================================"
echo " Final cleanup"
echo "============================================================"
echo

cleanup

###############################################################################
# Final result
###############################################################################

echo
echo "============================================================"
echo " Debian Wheezy ARMEL rootfs completed"
echo "============================================================"
echo
echo "Rootfs:"
echo "  $ROOTFS"
echo
echo "Architecture:"
echo "  $ARCH"
echo
echo "Distribution:"
echo "  Debian GNU/Linux 7 Wheezy"
echo
echo "Root device:"
echo "  /dev/mmcblk0p2"
echo
echo "Init:"
echo "  /sbin/init"
echo
echo "============================================================"