#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Debian 7 Wheezy ARMEL rootfs builder
#
# Target:
#   HTC HD2 / HTC Leo
#
# CPU:
#   Qualcomm QSD8250 / ARMv7
#
# Architecture:
#   ARMEL 32-bit
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
#   - USB Ethernet fallback
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

# Debian Wheezy is EOL.
MIRROR="http://archive.debian.org/debian"

###############################################################################
# Network configuration
###############################################################################

# HTC HD2 Wi-Fi interface.
WIFI_IFACE="wlan0"

# USB Ethernet gadget interface.
USB_IFACE="usb0"

# USB fallback address.
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
# Cleanup
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
# Prepare output
###############################################################################

echo "==> Preparing output directory"

rm -rf "$OUTPUT_DIR"
mkdir -p "$ROOTFS"

###############################################################################
# Bootstrap Debian
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
# Install QEMU
###############################################################################

echo
echo "==> Installing QEMU ARM emulator into rootfs"

cp \
    /usr/bin/qemu-arm-static \
    "$ROOTFS/usr/bin/qemu-arm-static"

###############################################################################
# Configure APT
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
# Prevent services from starting in chroot
###############################################################################

echo "==> Creating policy-rc.d"

cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF

chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

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
#
# IMPORTANT:
# Wi-Fi is intentionally NOT managed by ifupdown.
# hd2-network manages Wi-Fi directly.
###############################################################################

echo "==> Configuring network"

mkdir -p "$ROOTFS/etc/network"

cat > "$ROOTFS/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

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
    psmisc \
    net-tools \
    ifupdown \
    iproute \
    iputils-ping \
    isc-dhcp-client \
    wireless-tools \
    wpasupplicant \
    openssh-server \
    openssh-client \
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
mkdir -p "$ROOTFS/var/run/wpa_supplicant"

cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=00
EOF

chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

chmod 755 "$ROOTFS/var/run/wpa_supplicant"

###############################################################################
# Wi-Fi CLI
###############################################################################

echo "==> Installing Wi-Fi CLI"

mkdir -p "$ROOTFS/usr/local/bin"

cat > "$ROOTFS/usr/local/bin/wifi" <<'WIFI_EOF'
#!/bin/sh

###############################################################################
# HTC HD2 Wi-Fi CLI
#
# Commands:
#   wifi test
#   wifi scan
#   wifi on
#   wifi off
#   wifi connect
#   wifi help
###############################################################################

IFACE="__WIFI_IFACE__"
CONF="/etc/wpa_supplicant/wpa_supplicant.conf"

###############################################################################
# Check interface
###############################################################################

wifi_exists()
{
    if ip link show "$IFACE" >/dev/null 2>&1; then
        return 0
    fi

    if ifconfig "$IFACE" >/dev/null 2>&1; then
        return 0
    fi

    echo
    echo "[FAIL] Wi-Fi interface $IFACE not found."
    echo
    echo "Possible causes:"
    echo "  - Wi-Fi kernel driver is not loaded"
    echo "  - Wi-Fi firmware is missing"
    echo "  - interface has another name"
    echo
    echo "Useful commands:"
    echo "  ifconfig -a"
    echo "  iwconfig"
    echo "  lsmod"
    echo "  dmesg | grep -i wifi"
    echo

    return 1
}

###############################################################################
# Wi-Fi ON
###############################################################################

wifi_on()
{
    wifi_exists || return 1

    echo "==> Enabling $IFACE"

    ifconfig "$IFACE" up 2>/dev/null || \
        ip link set "$IFACE" up 2>/dev/null || {

        echo "[FAIL] Unable to enable $IFACE"
        return 1
    }

    echo "[ OK ] Wi-Fi enabled"
}

###############################################################################
# Wi-Fi OFF
###############################################################################

wifi_off()
{
    wifi_exists || return 1

    echo "==> Disabling Wi-Fi"

    killall wpa_supplicant 2>/dev/null || true
    killall dhclient 2>/dev/null || true

    ifconfig "$IFACE" 0.0.0.0 2>/dev/null || true

    ifconfig "$IFACE" down 2>/dev/null || \
        ip link set "$IFACE" down 2>/dev/null || true

    echo "[ OK ] Wi-Fi disabled"
}

###############################################################################
# Wi-Fi SCAN
###############################################################################

wifi_scan()
{
    wifi_exists || return 1

    wifi_on >/dev/null 2>&1 || true

    echo
    echo "========================================"
    echo " Wi-Fi scan"
    echo "========================================"
    echo

    ###########################################################################
    # Legacy WEXT
    ###########################################################################

    if command -v iwlist >/dev/null 2>&1; then

        echo "Scanning with iwlist..."
        echo

        if iwlist "$IFACE" scan 2>/dev/null; then
            return 0
        fi

    fi

    ###########################################################################
    # nl80211
    ###########################################################################

    if command -v iw >/dev/null 2>&1; then

        echo "Scanning with iw..."
        echo

        if iw dev "$IFACE" scan 2>/dev/null; then
            return 0
        fi

    fi

    echo
    echo "[FAIL] Wi-Fi scan failed."
    echo
    echo "The kernel driver may not support:"
    echo "  - WEXT"
    echo "  - nl80211"
    echo

    return 1
}

###############################################################################
# Wi-Fi CONNECT
###############################################################################

wifi_connect()
{
    wifi_exists || return 1

    SSID="$*"

    ###########################################################################
    # Ask SSID if not supplied
    ###########################################################################

    if [ -z "$SSID" ]; then

        echo
        echo "SSID:"
        printf "> "

        IFS= read -r SSID

    fi

    if [ -z "$SSID" ]; then
        echo "[FAIL] SSID cannot be empty."
        return 1
    fi

    echo
    echo "SSID: $SSID"
    echo

    ###########################################################################
    # Ask password
    ###########################################################################

    printf "Password (leave empty for OPEN network): "

    stty -echo 2>/dev/null || true
    IFS= read -r PASSWORD
    stty echo 2>/dev/null || true

    echo

    ###########################################################################
    # Prepare
    ###########################################################################

    mkdir -p /etc/wpa_supplicant
    mkdir -p /var/run/wpa_supplicant

    chmod 700 /etc/wpa_supplicant
    chmod 755 /var/run/wpa_supplicant

    killall wpa_supplicant 2>/dev/null || true
    killall dhclient 2>/dev/null || true

    ifconfig "$IFACE" up 2>/dev/null || \
        ip link set "$IFACE" up 2>/dev/null || {

        echo "[FAIL] Unable to enable $IFACE."
        return 1
    }

    ###########################################################################
    # Temporary WPA configuration
    ###########################################################################

    TEMP_CONF="/tmp/wpa_supplicant.conf.$$"

    cat > "$TEMP_CONF" <<EOF2
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=00

network={
    ssid="$SSID"
EOF2

    ###########################################################################
    # WPA/WPA2 password
    ###########################################################################

    if [ -n "$PASSWORD" ]; then

        WPA_LINE="$(
            wpa_passphrase "$SSID" "$PASSWORD" 2>/dev/null \
            | sed -n 's/^[[:space:]]*psk=.*$/    psk=\1/p' \
            | tail -n 1
        )"

        if [ -z "$WPA_LINE" ]; then

            rm -f "$TEMP_CONF"

            echo "[FAIL] Unable to generate WPA configuration."

            return 1
        fi

        echo "$WPA_LINE" >> "$TEMP_CONF"

    else

        #######################################################################
        # Open Wi-Fi
        #######################################################################

        cat >> "$TEMP_CONF" <<EOF2
    key_mgmt=NONE
EOF2

    fi

    cat >> "$TEMP_CONF" <<EOF2
}
EOF2

    chmod 600 "$TEMP_CONF"

    mv "$TEMP_CONF" "$CONF"

    ###########################################################################
    # Start wpa_supplicant
    #
    # HTC HD2-era drivers commonly use WEXT.
    ###########################################################################

    echo
    echo "Connecting..."
    echo

    if ! wpa_supplicant \
        -B \
        -D wext \
        -i "$IFACE" \
        -c "$CONF" \
        2>/dev/null; then

        echo "WEXT failed."
        echo "Trying automatic driver..."

        killall wpa_supplicant 2>/dev/null || true

        if ! wpa_supplicant \
            -B \
            -i "$IFACE" \
            -c "$CONF" \
            2>/dev/null; then

            echo
            echo "[FAIL] wpa_supplicant could not start."
            return 1
        fi
    fi

    ###########################################################################
    # Wait for association
    ###########################################################################

    echo "Waiting for Wi-Fi association..."

    COUNT=0

    while [ "$COUNT" -lt 20 ]; do

        if wpa_cli \
            -i "$IFACE" \
            status 2>/dev/null \
            | grep -q '^wpa_state=COMPLETED'; then

            break
        fi

        sleep 1

        COUNT=$((COUNT + 1))

    done

    ###########################################################################
    # Check association
    ###########################################################################

    if ! wpa_cli \
        -i "$IFACE" \
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

    echo
    echo "[ OK ] Wi-Fi connected"

    ###########################################################################
    # DHCP
    ###########################################################################

    echo
    echo "Requesting DHCP..."

    dhclient -r "$IFACE" 2>/dev/null || true

    if ! dhclient "$IFACE" 2>/dev/null; then

        echo "[FAIL] DHCP failed."

        return 1
    fi

    ###########################################################################
    # Show IP
    ###########################################################################

    IP="$(
        ip -4 addr show "$IFACE" 2>/dev/null \
        | sed -n 's/.*inet [0-9.]*\/.*/\1/p' \
        | head -n 1
    )"

    echo
    echo "[ OK ] Network configured"
    echo "IP address: ${IP:-unknown}"

    ###########################################################################
    # SSH information
    ###########################################################################

    echo
    echo "SSH:"
    echo "  ssh root@${IP:-<IP_ADDRESS>}"
    echo

    return 0
}

###############################################################################
# Wi-Fi TEST
###############################################################################

wifi_test()
{
    echo
    echo "========================================"
    echo " HTC HD2 Wi-Fi test"
    echo "========================================"
    echo

    echo "Interface: $IFACE"
    echo

    if ! wifi_exists; then
        return 1
    fi

    echo "[ OK ] Interface detected"

    ###########################################################################
    # Interface state
    ###########################################################################

    echo
    echo "Interface state:"

    ip link show "$IFACE" 2>/dev/null || \
        ifconfig "$IFACE" 2>/dev/null || true

    ###########################################################################
    # Wireless state
    ###########################################################################

    echo
    echo "Wireless state:"

    iwconfig "$IFACE" 2>/dev/null || \
        echo "Wireless information unavailable."

    ###########################################################################
    # IP address
    ###########################################################################

    echo
    echo "IP address:"

    ip addr show "$IFACE" 2>/dev/null || \
        ifconfig "$IFACE" 2>/dev/null || true

    ###########################################################################
    # Route
    ###########################################################################

    echo
    echo "Default route:"

    ip route 2>/dev/null | grep '^default' || \
        route -n 2>/dev/null | head

    ###########################################################################
    # Internet
    ###########################################################################

    echo
    echo "Internet test:"

    if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then

        echo "[ OK ] Internet reachable"

    else

        echo "[FAIL] Internet unreachable"

        return 1
    fi

    ###########################################################################
    # DNS
    ###########################################################################

    echo
    echo "DNS test:"

    if getent hosts debian.org >/dev/null 2>&1; then

        echo "[ OK ] DNS working"

    else

        echo "[FAIL] DNS unavailable"

        return 1
    fi

    ###########################################################################
    # Result
    ###########################################################################

    echo
    echo "Wi-Fi test: PASS"
    echo

    return 0
}

###############################################################################
# HELP
###############################################################################

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
    echo "      Test Wi-Fi interface, Internet and DNS"
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
    echo "      Connect using the specified SSID"
    echo

    echo "  wifi help"
    echo "      Show this help"
    echo
}

###############################################################################
# Main
###############################################################################

case "${1:-help}" in

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
        wifi_connect "$@"
        ;;

    help|-h|--help)
        wifi_help
        ;;

    *)
        echo "Unknown Wi-Fi command: $1"
        echo
        wifi_help
        exit 1
        ;;

esac
WIFI_EOF

###############################################################################
# Replace Wi-Fi interface placeholder
###############################################################################

sed -i \
    "s/__WIFI_IFACE__/$WIFI_IFACE/g" \
    "$ROOTFS/usr/local/bin/wifi"

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

    # Ensure settings exist even if Debian's default config differs.
    if ! grep -q '^PermitRootLogin' "$ROOTFS/etc/ssh/sshd_config"; then
        echo "PermitRootLogin yes" >> "$ROOTFS/etc/ssh/sshd_config"
    fi

    if ! grep -q '^PasswordAuthentication' "$ROOTFS/etc/ssh/sshd_config"; then
        echo "PasswordAuthentication yes" >> "$ROOTFS/etc/ssh/sshd_config"
    fi

fi

###############################################################################
# Enable SSH
###############################################################################

if [ -x "$ROOTFS/etc/init.d/ssh" ]; then

    echo "==> Enabling SSH at boot"

    chroot "$ROOTFS" \
        update-rc.d ssh defaults || true

fi

###############################################################################
# Generate SSH host keys
###############################################################################

echo "==> Checking SSH host keys"

if ! ls "$ROOTFS/etc/ssh"/ssh_host_* >/dev/null 2>&1; then

    echo "==> Generating SSH host keys"

    chroot "$ROOTFS" \
        ssh-keygen -A || true

fi

###############################################################################
# HTC HD2 network startup service
###############################################################################

echo "==> Creating HTC HD2 network startup service"

cat > "$ROOTFS/etc/init.d/hd2-network" <<EOF
#!/bin/sh

### BEGIN INIT INFO
# Provides:          hd2-network
# Required-Start:    \$remote_fs
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

###############################################################################
# Start Wi-Fi
###############################################################################

start_wifi()
{
    if [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        return 1
    fi

    if ! grep -q '^[[:space:]]*network=' \
        /etc/wpa_supplicant/wpa_supplicant.conf; then

        return 1
    fi

    echo "==> Saved Wi-Fi configuration found."

    if ! ip link show "\$WIFI_IFACE" >/dev/null 2>&1; then
        echo "[INFO] Wi-Fi interface \$WIFI_IFACE not available."
        return 1
    fi

    ifconfig "\$WIFI_IFACE" up 2>/dev/null || \
        ip link set "\$WIFI_IFACE" up 2>/dev/null || true

    killall wpa_supplicant 2>/dev/null || true
    killall dhclient 2>/dev/null || true

    ###########################################################################
    # Try WEXT first.
    ###########################################################################

    if wpa_supplicant \
        -B \
        -D wext \
        -i "\$WIFI_IFACE" \
        -c /etc/wpa_supplicant/wpa_supplicant.conf \
        2>/dev/null; then

        echo "==> Waiting for Wi-Fi..."

        COUNT=0

        while [ "\$COUNT" -lt 15 ]; do

            if wpa_cli \
                -i "\$WIFI_IFACE" \
                status 2>/dev/null \
                | grep -q '^wpa_state=COMPLETED'; then

                break
            fi

            sleep 1
            COUNT=\$((COUNT + 1))

        done

        if wpa_cli \
            -i "\$WIFI_IFACE" \
            status 2>/dev/null \
            | grep -q '^wpa_state=COMPLETED'; then

            if dhclient "\$WIFI_IFACE" 2>/dev/null; then

                echo "[ OK ] Wi-Fi connected."

                return 0
            fi
        fi

    fi

    ###########################################################################
    # WEXT failed. Try automatic driver.
    ###########################################################################

    killall wpa_supplicant 2>/dev/null || true

    echo "==> Trying automatic Wi-Fi driver."

    if wpa_supplicant \
        -B \
        -i "\$WIFI_IFACE" \
        -c /etc/wpa_supplicant/wpa_supplicant.conf \
        2>/dev/null; then

        echo "==> Waiting for Wi-Fi..."

        COUNT=0

        while [ "\$COUNT" -lt 15 ]; do

            if wpa_cli \
                -i "\$WIFI_IFACE" \
                status 2>/dev/null \
                | grep -q '^wpa_state=COMPLETED'; then

                break
            fi

            sleep 1
            COUNT=\$((COUNT + 1))

        done

        if wpa_cli \
            -i "\$WIFI_IFACE" \
            status 2>/dev/null \
            | grep -q '^wpa_state=COMPLETED'; then

            if dhclient "\$WIFI_IFACE" 2>/dev/null; then

                echo "[ OK ] Wi-Fi connected."

                return 0
            fi
        fi

    fi

    killall wpa_supplicant 2>/dev/null || true

    echo "[INFO] Automatic Wi-Fi connection failed."

    return 1
}

###############################################################################
# USB Ethernet fallback
###############################################################################

start_usb()
{
    echo "==> Trying USB Ethernet fallback."

    ###########################################################################
    # Requires kernel support for USB gadget Ethernet.
    ###########################################################################

    modprobe g_ether 2>/dev/null || true

    sleep 1

    if ! ip link show "\$USB_IFACE" >/dev/null 2>&1; then

        echo "[INFO] USB Ethernet interface not available."

        return 1
    fi

    ifconfig "\$USB_IFACE" \
        "\$USB_IP" \
        netmask "\$USB_NETMASK" \
        up 2>/dev/null || {

        ip addr add \
            "\$USB_IP/24" \
            dev "\$USB_IFACE" \
            2>/dev/null || true

        ip link set \
            "\$USB_IFACE" \
            up \
            2>/dev/null || true
    }

    echo "[ OK ] USB Ethernet available."
    echo "      IP: \$USB_IP"

    return 0
}

###############################################################################
# Main
###############################################################################

case "\$1" in

    start)

        echo "==> HTC HD2 network initialization"

        #######################################################################
        # Wi-Fi first
        #######################################################################

        if start_wifi; then
            exit 0
        fi

        #######################################################################
        # USB fallback
        #######################################################################

        echo "==> Wi-Fi unavailable or not configured."

        start_usb || true

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
# Enable HTC HD2 network service
###############################################################################

echo "==> Enabling HTC HD2 network service"

chroot "$ROOTFS" \
    update-rc.d hd2-network defaults || true

###############################################################################
# Network information command
###############################################################################

echo "==> Installing netinfo"

cat > "$ROOTFS/usr/local/bin/netinfo" <<'EOF'
#!/bin/sh

echo
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
echo "Wi-Fi:"
iwconfig wlan0 2>/dev/null || true

echo
echo "SSH:"
echo "  service ssh start"
echo "  service ssh status"
echo
EOF

chmod 755 "$ROOTFS/usr/local/bin/netinfo"

###############################################################################
# Verify installed files
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
# Verify commands
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
    /sbin/wpa_cli
    /sbin/dhclient
    /usr/sbin/sshd
    /usr/bin/wpa_passphrase
    /usr/sbin/iwlist
    /usr/bin/iwconfig
    /usr/local/bin/wifi
    /usr/local/bin/netinfo
)

for file in "${IMPORTANT_COMMANDS[@]}"; do

    if [ -e "$ROOTFS$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[WARN] Missing: $file"
    fi

done

###############################################################################
# Verify Wi-Fi script syntax
###############################################################################

echo
echo "==> Checking Wi-Fi CLI syntax"

if chroot "$ROOTFS" /bin/sh -n /usr/local/bin/wifi; then
    echo "[ OK ] wifi script syntax"
else
    echo "[FAIL] wifi script syntax error"
    exit 1
fi

###############################################################################
# Verify network service syntax
###############################################################################

echo
echo "==> Checking network service syntax"

if chroot "$ROOTFS" /bin/sh -n /etc/init.d/hd2-network; then
    echo "[ OK ] hd2-network syntax"
else
    echo "[FAIL] hd2-network syntax error"
    exit 1
fi

###############################################################################
# Verify architecture
###############################################################################

echo
echo "==> Verifying Debian architecture"

if [ -f "$ROOTFS/var/lib/dpkg/arch" ]; then

    echo "dpkg architecture information:"
    cat "$ROOTFS/var/lib/dpkg/arch"

fi

###############################################################################
# Remove QEMU
###############################################################################

echo
echo "==> Removing QEMU from final rootfs"

rm -f "$ROOTFS/usr/bin/qemu-arm-static"

###############################################################################
# Remove policy-rc.d
###############################################################################

echo "==> Removing temporary policy-rc.d"

rm -f "$ROOTFS/usr/sbin/policy-rc.d"

###############################################################################
# Clean APT
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

chmod 1777 "$ROOTFS/tmp"

###############################################################################
# Final DNS
###############################################################################

echo "==> Preparing final DNS configuration"

rm -f "$ROOTFS/etc/resolv.conf"

cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

chmod 644 "$ROOTFS/etc/resolv.conf"

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

SSH:
  Root password must be configured manually using passwd.

Rootfs builder: GitHub Actions
EOF

###############################################################################
# Final verification
###############################################################################

echo
echo "============================================================"
echo " Final rootfs verification"
echo "============================================================"
echo

if [ ! -x "$ROOTFS/sbin/init" ]; then
    echo "[FAIL] /sbin/init missing"
    exit 1
fi

if [ ! -x "$ROOTFS/usr/local/bin/wifi" ]; then
    echo "[FAIL] wifi command missing"
    exit 1
fi

if [ ! -x "$ROOTFS/usr/local/bin/netinfo" ]; then
    echo "[FAIL] netinfo command missing"
    exit 1
fi

if [ ! -f "$ROOTFS/etc/init.d/ssh" ]; then
    echo "[FAIL] SSH init script missing"
    exit 1
fi

if [ ! -f "$ROOTFS/etc/init.d/hd2-network" ]; then
    echo "[FAIL] hd2-network init script missing"
    exit 1
fi

echo "[ OK ] /sbin/init"
echo "[ OK ] Wi-Fi CLI"
echo "[ OK ] Network service"
echo "[ OK ] SSH"
echo "[ OK ] DNS configuration"

###############################################################################
# Cleanup mounts
###############################################################################

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
echo "  passwd"
echo "  service ssh start"
echo "  service ssh status"
echo

echo "USB fallback:"
echo "  $USB_IP"
echo

echo "============================================================"
echo " Build successful"
echo "============================================================"