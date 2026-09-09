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
#
# Features:
#   - SysV init
#   - Wi-Fi CLI
#   - Wi-Fi scan
#   - Wi-Fi connect
#   - Wi-Fi on/off
#   - Wi-Fi diagnostics
#   - DHCP
#   - SSH server
#   - SSH auto-start
#   - USB Ethernet fallback if kernel supports g_ether
###############################################################################

###############################################################################
# Paths
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
# Network configuration
###############################################################################

# HTC HD2 Wi-Fi interface.
# Change this if your kernel uses another interface name.
WIFI_IFACE="wlan0"

# USB Ethernet fallback address.
USB_IFACE="usb0"
USB_IP="192.168.7.2"
USB_NETMASK="255.255.255.0"

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
    cp
    sed
    grep
    find
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
# Temporary DNS for build
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
# Base network configuration
###############################################################################

echo "==> Configuring network"

mkdir -p "$ROOTFS/etc/network"

cat > "$ROOTFS/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

allow-hotplug $WIFI_IFACE
iface $WIFI_IFACE inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

allow-hotplug $USB_IFACE
iface $USB_IFACE inet static
    address $USB_IP
    netmask $USB_NETMASK
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
    isc-dhcp-client \
    wireless-tools \
    wpasupplicant \
    openssh-server \
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
# Wi-Fi configuration
###############################################################################

echo "==> Configuring wpa_supplicant"

mkdir -p "$ROOTFS/etc/wpa_supplicant"

cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=00
EOF

chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

###############################################################################
# Wi-Fi CLI
###############################################################################

echo "==> Installing Wi-Fi CLI"

mkdir -p "$ROOTFS/usr/local/bin"

cat > "$ROOTFS/usr/local/bin/wifi" <<EOF'
#!/bin/sh

###############################################################################
# HTC HD2 Wi-Fi command
#
# Commands:
#   wifi test
#   wifi scan
#   wifi on
#   wifi off
#   wifi connect
#   wifi help
###############################################################################

IFACE="$WIFI_IFACE"
CONF="/etc/wpa_supplicant/wpa_supplicant.conf"

###############################################################################
# Helpers
###############################################################################

wifi_exists()
{
    if ip link show "\$IFACE" >/dev/null 2>&1; then
        return 0
    fi

    if ifconfig "\$IFACE" >/dev/null 2>&1; then
        return 0
    fi

    echo "[FAIL] Wi-Fi interface \$IFACE not found."
    echo
    echo "Possible causes:"
    echo "  - Wi-Fi kernel driver is not loaded"
    echo "  - Wi-Fi firmware is missing"
    echo "  - interface has another name"
    echo

    return 1
}

wifi_on()
{
    wifi_exists || return 1

    echo "==> Enabling \$IFACE"

    ifconfig "\$IFACE" up 2>/dev/null || \
        ip link set "\$IFACE" up 2>/dev/null || {
            echo "[FAIL] Unable to enable \$IFACE"
            return 1
        }

    echo "[ OK ] Wi-Fi enabled"
}

wifi_off()
{
    wifi_exists || return 1

    echo "==> Disabling Wi-Fi"

    killall wpa_supplicant 2>/dev/null || true
    killall dhclient 2>/dev/null || true

    ifconfig "\$IFACE" 0.0.0.0 2>/dev/null || true

    ifconfig "\$IFACE" down 2>/dev/null || \
        ip link set "\$IFACE" down 2>/dev/null || true

    echo "[ OK ] Wi-Fi disabled"
}

wifi_scan()
{
    wifi_exists || return 1

    wifi_on >/dev/null 2>&1 || true

    echo
    echo "========================================"
    echo " Wi-Fi scan"
    echo "========================================"
    echo

    # Old HTC/legacy drivers commonly support WEXT.
    if command -v iwlist >/dev/null 2>&1; then
        echo "Using iwlist..."
        echo

        if iwlist "\$IFACE" scan 2>/dev/null; then
            return 0
        fi
    fi

    # Newer drivers may support nl80211.
    if command -v iw >/dev/null 2>&1; then
        echo "Using iw..."
        echo

        if iw dev "\$IFACE" scan 2>/dev/null; then
            return 0
        fi
    fi

    echo "[FAIL] Wi-Fi scan failed."
    echo
    echo "The kernel driver may not support scanning through"
    echo "wireless-tools/WEXT or nl80211."

    return 1
}

wifi_connect()
{
    wifi_exists || return 1

    SSID="\$*"

    if [ -z "\$SSID" ]; then
        echo
        echo "SSID:"
        printf "> "
        IFS= read -r SSID
    fi

    if [ -z "\$SSID" ]; then
        echo "[FAIL] SSID cannot be empty."
        return 1
    fi

    echo
    echo "SSID: \$SSID"
    echo

    printf "Password (leave empty for OPEN network): "
    stty -echo 2>/dev/null || true
    IFS= read -r PASSWORD
    stty echo 2>/dev/null || true
    echo

    mkdir -p /etc/wpa_supplicant

    chmod 700 /etc/wpa_supplicant

    killall wpa_supplicant 2>/dev/null || true
    killall dhclient 2>/dev/null || true

    ifconfig "\$IFACE" up 2>/dev/null || \
        ip link set "\$IFACE" up 2>/dev/null || {
            echo "[FAIL] Unable to enable \$IFACE."
            return 1
        }

    TEMP_CONF="/tmp/wpa_supplicant.conf.\$\$"

    cat > "\$TEMP_CONF" <<EOF2
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=00

network={
    ssid="\$SSID"
EOF2

    if [ -n "\$PASSWORD" ]; then

        WPA_LINE="\$(wpa_passphrase "\$SSID" "\$PASSWORD" 2>/dev/null \
            | sed -n 's/^[[:space:]]*psk=\(.*\)$/    psk=\1/p' \
            | tail -n 1)"

        if [ -z "\$WPA_LINE" ]; then
            rm -f "\$TEMP_CONF"
            echo "[FAIL] Unable to generate WPA configuration."
            return 1
        fi

        echo "\$WPA_LINE" >> "\$TEMP_CONF"

    else

        cat >> "\$TEMP_CONF" <<EOF2
    key_mgmt=NONE
EOF2

    fi

    cat >> "\$TEMP_CONF" <<EOF2
}
EOF2

    chmod 600 "\$TEMP_CONF"

    mv "\$TEMP_CONF" "\$CONF"

    echo
    echo "Connecting..."
    echo

    # First try WEXT for old HTC HD2-era drivers.
    if ! wpa_supplicant \
        -B \
        -D wext \
        -i "\$IFACE" \
        -c "\$CONF" 2>/dev/null; then

        # Fallback to automatic backend.
        if ! wpa_supplicant \
            -B \
            -i "\$IFACE" \
            -c "\$CONF" 2>/dev/null; then

            echo "[FAIL] wpa_supplicant could not start."
            return 1
        fi
    fi

    echo "Waiting for Wi-Fi association..."

    COUNT=0

    while [ "\$COUNT" -lt 20 ]; do

        if wpa_cli \
            -i "\$IFACE" \
            status 2>/dev/null \
            | grep -q '^wpa_state=COMPLETED'; then

            break
        fi

        sleep 1
        COUNT=\$((COUNT + 1))

    done

    if ! wpa_cli \
        -i "\$IFACE" \
        status 2>/dev/null \
        | grep -q '^wpa_state=COMPLETED'; then

        echo
        echo "[FAIL] Wi-Fi association failed."
        echo
        echo "Check:"
        echo "  - SSID"
        echo "  - password"
        echo "  - Wi-Fi driver"
        echo "  - Wi-Fi firmware"
        echo

        return 1
    fi

    echo "[ OK ] Wi-Fi connected"

    echo
    echo "Requesting DHCP..."

    dhclient -r "\$IFACE" 2>/dev/null || true

    if ! dhclient "\$IFACE" 2>/dev/null; then
        echo "[FAIL] DHCP failed."
        return 1
    fi

    IP="\$(ip -4 addr show "\$IFACE" 2>/dev/null \
        | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' \
        | head -n 1)"

    echo
    echo "[ OK ] Network configured"
    echo "IP address: \${IP:-unknown}"

    echo
    echo "SSH:"
    echo "  ssh root@\${IP:-<IP_ADDRESS>}"
    echo
}

wifi_test()
{
    echo
    echo "========================================"
    echo " HTC HD2 Wi-Fi test"
    echo "========================================"
    echo

    echo "Interface: \$IFACE"
    echo

    if ! wifi_exists; then
        return 1
    fi

    echo "[ OK ] Interface detected"

    echo
    echo "Interface state:"
    ip link show "\$IFACE" 2>/dev/null || \
        ifconfig "\$IFACE" 2>/dev/null || true

    echo
    echo "Wireless state:"

    iwconfig "\$IFACE" 2>/dev/null || \
        iw dev "\$IFACE" link 2>/dev/null || \
        echo "Wireless information unavailable."

    echo
    echo "IP address:"

    ip addr show "\$IFACE" 2>/dev/null || \
        ifconfig "\$IFACE" 2>/dev/null || true

    echo
    echo "Default route:"

    ip route 2>/dev/null | grep '^default' || \
        route -n 2>/dev/null | head

    echo
    echo "Gateway/Internet test:"

    if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
        echo "[ OK ] Internet reachable"
    else
        echo "[FAIL] Internet unreachable"
        return 1
    fi

    echo
    echo "DNS test:"

    if getent hosts debian.org >/dev/null 2>&1; then
        echo "[ OK ] DNS working"
    else
        echo "[FAIL] DNS unavailable"
        return 1
    fi

    echo
    echo "Wi-Fi test: PASS"
    echo
}

wifi_help()
{
    echo
    echo "========================================"
    echo " HTC HD2 Wi-Fi"
    echo "========================================"
    echo
    echo "Commands:"
    echo
    echo "  wifi test"
    echo "      Test Wi-Fi interface, network and DNS"
    echo
    echo "  wifi scan"
    echo "      Scan nearby Wi-Fi networks"
    echo
    echo "  wifi on"
    echo "      Enable Wi-Fi"
    echo
    echo "  wifi off"
    echo "      Disable Wi-Fi"
    echo
    echo "  wifi connect"
    echo "      Ask for SSID and password"
    echo
    echo "  wifi connect SSID"
    echo "      Connect directly using SSID"
    echo
    echo "  wifi help"
    echo "      Show this help"
    echo
}

case "\${1:-help}" in

    test)
        wifi_test
        ;;

    scan)
        wifi_scan
        ;;

    on)
        wifi_on
        ;;

    off)
        wifi_off
        ;;

    connect)
        shift
        wifi_connect "\$@"
        ;;

    help|-h|--help)
        wifi_help
        ;;

    *)
        echo "Unknown Wi-Fi command: \$1"
        echo
        wifi_help
        exit 1
        ;;

esac
EOF

chmod 755 "$ROOTFS/usr/local/bin/wifi"

###############################################################################
# SSH configuration
###############################################################################

echo "==> Configuring SSH"

mkdir -p "$ROOTFS/etc/ssh"

if [ -f "$ROOTFS/etc/ssh/sshd_config" ]; then

    sed -i \
        -e 's/^#*[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' \
        "$ROOTFS/etc/ssh/sshd_config"

    sed -i \
        -e 's/^#*[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/' \
        "$ROOTFS/etc/ssh/sshd_config"

fi

###############################################################################
# SSH init script
###############################################################################

if [ -x "$ROOTFS/etc/init.d/ssh" ]; then

    echo "==> Enabling SSH at boot"

    chroot "$ROOTFS" \
        update-rc.d ssh defaults || true

fi

###############################################################################
# SSH host keys
###############################################################################

echo "==> Checking SSH host keys"

mkdir -p "$ROOTFS/etc/ssh"

if ! ls "$ROOTFS/etc/ssh"/ssh_host_* >/dev/null 2>&1; then

    echo "==> Generating SSH host keys"

    chroot "$ROOTFS" \
        ssh-keygen -A || true

fi

###############################################################################
# Automatic Wi-Fi startup
###############################################################################

echo "==> Creating Wi-Fi startup service"

cat > "$ROOTFS/etc/init.d/hd2-network" <<EOF
#!/bin/sh

### BEGIN INIT INFO
# Provides:          hd2-network
# Required-Start:    \$networking
# Required-Stop:
# Should-Start:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: HTC HD2 network initialization
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin

WIFI_IFACE="$WIFI_IFACE"
USB_IFACE="$USB_IFACE"
USB_IP="$USB_IP"
USB_NETMASK="$USB_NETMASK"

case "\$1" in

    start)

        echo "==> HTC HD2 network initialization"

        #######################################################################
        # Try Wi-Fi if a saved configuration exists.
        #######################################################################

        if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] && \
           grep -q '^[[:space:]]*network=' \
           /etc/wpa_supplicant/wpa_supplicant.conf; then

            echo "==> Saved Wi-Fi configuration found."

            if ip link show "\$WIFI_IFACE" >/dev/null 2>&1; then

                ifconfig "\$WIFI_IFACE" up 2>/dev/null || \
                    ip link set "\$WIFI_IFACE" up 2>/dev/null || true

                killall wpa_supplicant 2>/dev/null || true
                killall dhclient 2>/dev/null || true

                if wpa_supplicant \
                    -B \
                    -D wext \
                    -i "\$WIFI_IFACE" \
                    -c /etc/wpa_supplicant/wpa_supplicant.conf \
                    2>/dev/null; then

                    sleep 3

                    if dhclient "\$WIFI_IFACE" 2>/dev/null; then
                        echo "[ OK ] Wi-Fi connected."

                        exit 0
                    fi
                fi

                #################################################################
                # Fallback to automatic wpa_supplicant driver.
                #################################################################

                killall wpa_supplicant 2>/dev/null || true

                if wpa_supplicant \
                    -B \
                    -i "\$WIFI_IFACE" \
                    -c /etc/wpa_supplicant/wpa_supplicant.conf \
                    2>/dev/null; then

                    sleep 3

                    if dhclient "\$WIFI_IFACE" 2>/dev/null; then
                        echo "[ OK ] Wi-Fi connected."

                        exit 0
                    fi
                fi

            fi

        fi

        #######################################################################
        # USB Ethernet fallback.
        #
        # Requires kernel support for USB gadget Ethernet, usually g_ether.
        #######################################################################

        echo "==> Wi-Fi unavailable or not configured."
        echo "==> Trying USB Ethernet fallback."

        modprobe g_ether 2>/dev/null || true

        sleep 1

        if ip link show "\$USB_IFACE" >/dev/null 2>&1; then

            ifconfig "\$USB_IFACE" \
                "\$USB_IP" \
                netmask "\$USB_NETMASK" \
                up 2>/dev/null || \
            ip addr add \
                "\$USB_IP/24" \
                dev "\$USB_IFACE" 2>/dev/null || true

            ip link set "\$USB_IFACE" up 2>/dev/null || true

            echo "[ OK ] USB Ethernet available."
            echo "      IP: \$USB_IP"

        else

            echo "[INFO] USB Ethernet interface not available."

        fi

        ;;

    stop)

        killall dhclient 2>/dev/null || true
        killall wpa_supplicant 2>/dev/null || true

        ifconfig "\$WIFI_IFACE" down 2>/dev/null || true
        ifconfig "\$USB_IFACE" down 2>/dev/null || true

        ;;

    restart)

        "\$0" stop
        sleep 1
        "\$0" start
        ;;

    *)

        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;

esac

exit 0
EOF

chmod 755 "$ROOTFS/etc/init.d/hd2-network"

###############################################################################
# Enable network startup
###############################################################################

echo "==> Enabling HTC HD2 network service"

chroot "$ROOTFS" \
    update-rc.d hd2-network defaults 2>/dev/null || true

###############################################################################
# Create convenient network information command
###############################################################################

cat > "$ROOTFS/usr/local/bin/netinfo" <<'EOF'
#!/bin/sh

echo "========================================"
echo " HTC HD2 Network"
echo "========================================"
echo

echo "Interfaces:"
ip link 2>/dev/null || ifconfig

echo
echo "Addresses:"
ip addr 2>/dev/null || ifconfig

echo
echo "Routes:"
ip route 2>/dev/null || route -n

echo
echo "DNS:"
cat /etc/resolv.conf 2>/dev/null || true

echo
echo "SSH:"
echo "  service ssh status"
echo
EOF

chmod 755 "$ROOTFS/usr/local/bin/netinfo"

###############################################################################
# Create Wi-Fi config directory
###############################################################################

mkdir -p "$ROOTFS/var/run/wpa_supplicant"
chmod 755 "$ROOTFS/var/run/wpa_supplicant"

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
# Create resolv.conf symlink
###############################################################################

echo "==> Preparing resolv.conf"

ln -sf /run/resolvconf/resolv.conf \
    "$ROOTFS/etc/resolv.conf" 2>/dev/null || true

###############################################################################
# Build information
###############################################################################

echo "==> Writing build information"

cat > "$ROOTFS/etc/htc-hd2-build-info" <<EOF
Target: HTC HD2
Codename: htc-leo
Distribution: Debian GNU/Linux 7 Wheezy
Architecture: armel
Root device: /dev/mmcblk0p2
Init: /sbin/init
Kernel: existing HTC HD2 kernel 2.6.32
Boot files: existing startup.txt, zImage and initrd.gz

Network:
  Wi-Fi interface: $WIFI_IFACE
  USB interface: $USB_IFACE
  USB fallback IP: $USB_IP

Features:
  Wi-Fi CLI
  Wi-Fi scan
  Wi-Fi connect
  Wi-Fi on/off
  Wi-Fi diagnostics
  DHCP
  SSH server
  SSH auto-start
  USB Ethernet fallback

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
# Verify important files
###############################################################################

echo
echo "============================================================"
echo " Verifying installed features"
echo "============================================================"
echo

VERIFY_FILES=(
    "$ROOTFS/sbin/init"
    "$ROOTFS/bin/sh"
    "$ROOTFS/usr/local/bin/wifi"
    "$ROOTFS/usr/local/bin/netinfo"
    "$ROOTFS/etc/network/interfaces"
    "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"
    "$ROOTFS/etc/init.d/hd2-network"
    "$ROOTFS/etc/init.d/ssh"
    "$ROOTFS/etc/ssh/sshd_config"
    "$ROOTFS/etc/htc-hd2-build-info"
)

for file in "${VERIFY_FILES[@]}"; do

    if [ -e "$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[FAIL] Missing: $file"
        exit 1
    fi

done

###############################################################################
# Verify commands inside rootfs
###############################################################################

echo
echo "==> Checking important commands"

IMPORTANT_COMMANDS=(
    /bin/sh
    /sbin/init
    /sbin/ifconfig
    /sbin/route
    /sbin/ip
    /sbin/wpa_supplicant
    /sbin/dhclient
    /usr/sbin/sshd
    /usr/bin/wpa_passphrase
    /usr/sbin/iwlist
    /usr/local/bin/wifi
)

for file in "${IMPORTANT_COMMANDS[@]}"; do

    if [ -e "$ROOTFS$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[WARN] Missing: $file"
    fi

done

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
echo "Wi-Fi:"
echo "  wifi test"
echo "  wifi scan"
echo "  wifi on"
echo "  wifi off"
echo "  wifi connect"
echo
echo "Network:"
echo "  netinfo"
echo
echo "SSH:"
echo "  service ssh start"
echo "  service ssh status"
echo
echo "USB fallback:"
echo "  $USB_IP"
echo
echo "============================================================"