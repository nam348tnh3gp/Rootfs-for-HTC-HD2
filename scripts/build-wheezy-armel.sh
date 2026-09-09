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
#   - USB Ethernet gadget fallback
#   - Framebuffer Xorg
#   - evdev touchscreen
#   - tslib tools
#   - xterm
#   - matchbox-keyboard
#   - Automatic GUI startup on tty1
#   - CLI remains available on tty2
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

WIFI_IFACE="wlan0"

# USB Ethernet gadget interface.
#
# IMPORTANT:
# This is for g_ether USB gadget mode.
# It is NOT a physical USB Ethernet adapter.
USB_IFACE="usb0"

USB_IP="192.168.7.2"
USB_NETMASK="255.255.255.0"

###############################################################################
# GUI configuration
###############################################################################

SCREEN_WIDTH="480"
SCREEN_HEIGHT="800"

# Approximate keyboard height.
KEYBOARD_HEIGHT="240"

DISPLAY_NUM=":0"
X_VT="vt1"

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

rm -f "$ROOTFS/etc/resolv.conf"

cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

chmod 644 "$ROOTFS/etc/resolv.conf"

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
# Network interfaces
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
    ca-certificates \
    xserver-xorg \
    xserver-xorg-core \
    xserver-xorg-video-fbdev \
    xserver-xorg-input-evdev \
    xinit \
    xterm \
    matchbox-keyboard \
    libts-bin

CHROOT

###############################################################################
# Verify init
###############################################################################

echo "==> Verifying /sbin/init"

if [ ! -x "$ROOTFS/sbin/init" ]; then
    echo "ERROR: /sbin/init was not created."
    exit 1
fi

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

IFACE="__WIFI_IFACE__"
CONF="/etc/wpa_supplicant/wpa_supplicant.conf"

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

wifi_scan()
{
    wifi_exists || return 1

    wifi_on >/dev/null 2>&1 || true

    echo
    echo "========================================"
    echo " Wi-Fi scan"
    echo "========================================"
    echo

    if command -v iwlist >/dev/null 2>&1; then
        echo "Scanning with iwlist..."
        echo

        if iwlist "$IFACE" scan 2>/dev/null; then
            return 0
        fi
    fi

    if command -v iw >/dev/null 2>&1; then
        echo "Scanning with iw..."
        echo

        if iw dev "$IFACE" scan 2>/dev/null; then
            return 0
        fi
    fi

    echo
    echo "[FAIL] Wi-Fi scan failed."
    return 1
}

wifi_connect()
{
    wifi_exists || return 1

    SSID="$*"

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

    printf "Password (leave empty for OPEN network): "

    stty -echo 2>/dev/null || true
    IFS= read -r PASSWORD
    stty echo 2>/dev/null || true

    echo

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

    TEMP_CONF="/tmp/wpa_supplicant.conf.$$"

    {
        echo "ctrl_interface=/var/run/wpa_supplicant"
        echo "update_config=1"
        echo "country=00"
        echo
        echo "network={"
        printf '    ssid="%s"\n' "$SSID"

        if [ -n "$PASSWORD" ]; then

            PSK="$(
                wpa_passphrase "$SSID" "$PASSWORD" 2>/dev/null \
                | sed -n 's/^[[:space:]]*psk=\(.*\)$/\1/p' \
                | tail -n 1
            )"

            if [ -z "$PSK" ]; then
                echo "}"
                rm -f "$TEMP_CONF"

                echo "[FAIL] Unable to generate WPA PSK."
                return 1
            fi

            printf '    psk=%s\n' "$PSK"

        else
            echo "    key_mgmt=NONE"
        fi

        echo "}"
    } > "$TEMP_CONF"

    chmod 600 "$TEMP_CONF"
    mv "$TEMP_CONF" "$CONF"

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

    if ! wpa_cli \
        -i "$IFACE" \
        status 2>/dev/null \
        | grep -q '^wpa_state=COMPLETED'; then

        echo
        echo "[FAIL] Wi-Fi association failed."
        return 1
    fi

    echo
    echo "[ OK ] Wi-Fi connected"
    echo
    echo "Requesting DHCP..."

    dhclient -r "$IFACE" 2>/dev/null || true

    if ! dhclient "$IFACE" 2>/dev/null; then
        echo "[FAIL] DHCP failed."
        return 1
    fi

    IP="$(
        ip -4 addr show "$IFACE" 2>/dev/null \
        | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' \
        | head -n 1
    )"

    echo
    echo "[ OK ] Network configured"
    echo "IP address: ${IP:-unknown}"
    echo
    echo "SSH:"
    echo "  ssh root@${IP:-<IP_ADDRESS>}"
    echo

    return 0
}

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

    echo
    echo "Interface state:"
    ip link show "$IFACE" 2>/dev/null || \
        ifconfig "$IFACE" 2>/dev/null || true

    echo
    echo "Wireless state:"
    iwconfig "$IFACE" 2>/dev/null || \
        echo "Wireless information unavailable."

    echo
    echo "IP address:"
    ip addr show "$IFACE" 2>/dev/null || \
        ifconfig "$IFACE" 2>/dev/null || true

    echo
    echo "Default route:"
    ip route 2>/dev/null | grep '^default' || \
        route -n 2>/dev/null | head

    echo
    echo "Internet test:"

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

    return 0
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
    echo "  wifi scan"
    echo "  wifi on"
    echo "  wifi off"
    echo "  wifi connect"
    echo "  wifi connect SSID"
    echo "  wifi help"
    echo
}

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

    grep -q '^PermitRootLogin' \
        "$ROOTFS/etc/ssh/sshd_config" || \
        echo "PermitRootLogin yes" \
        >> "$ROOTFS/etc/ssh/sshd_config"

    grep -q '^PasswordAuthentication' \
        "$ROOTFS/etc/ssh/sshd_config" || \
        echo "PasswordAuthentication yes" \
        >> "$ROOTFS/etc/ssh/sshd_config"
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

    if wpa_supplicant \
        -B \
        -D wext \
        -i "\$WIFI_IFACE" \
        -c /etc/wpa_supplicant/wpa_supplicant.conf \
        2>/dev/null; then

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

    echo "==> Trying automatic Wi-Fi driver."

    if wpa_supplicant \
        -B \
        -i "\$WIFI_IFACE" \
        -c /etc/wpa_supplicant/wpa_supplicant.conf \
        2>/dev/null; then

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

start_usb()
{
    echo "==> Trying USB Ethernet gadget fallback."

    modprobe g_ether 2>/dev/null || true

    sleep 1

    if ! ip link show "\$USB_IFACE" >/dev/null 2>&1; then
        echo "[INFO] USB Ethernet gadget interface not available."
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

    echo "[ OK ] USB Ethernet gadget available."
    echo "      IP: \$USB_IP"

    return 0
}

case "\$1" in

    start)

        echo "==> HTC HD2 network initialization"

        if start_wifi; then
            exit 0
        fi

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
# Enable network service
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
# X11 directories
###############################################################################

echo
echo "============================================================"
echo " Configuring HTC HD2 X11 GUI"
echo "============================================================"
echo

mkdir -p "$ROOTFS/root"
mkdir -p "$ROOTFS/etc/X11/xorg.conf.d"
mkdir -p "$ROOTFS/etc/X11/xinit"

###############################################################################
# Xorg framebuffer + touchscreen configuration
###############################################################################

cat > "$ROOTFS/etc/X11/xorg.conf.d/10-htc-hd2.conf" <<'EOF'
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection

Section "Device"
    Identifier "HTC HD2 framebuffer"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier "HTC HD2 screen"
    Device "HTC HD2 framebuffer"
    DefaultDepth 16
EndSection

Section "InputClass"
    Identifier "HTC HD2 touchscreen"
    MatchIsTouchscreen "on"
    Driver "evdev"
EndSection
EOF

###############################################################################
# TSLIB configuration
###############################################################################

cat > "$ROOTFS/etc/ts.conf" <<'EOF'
module_raw input
module linear
module dejitter
EOF

###############################################################################
# Touchscreen helper
###############################################################################

cat > "$ROOTFS/usr/local/bin/touchscreen" <<'EOF'
#!/bin/sh

find_touchscreen()
{
    for event in /dev/input/event*; do

        [ -e "$event" ] || continue

        NAME=""

        EVENT_NAME="/sys/class/input/$(basename "$event")/device/name"

        if [ -f "$EVENT_NAME" ]; then
            NAME="$(cat "$EVENT_NAME" 2>/dev/null || true)"
        fi

        case "$NAME" in
            *touch*|*Touch*|*TOUCH*|*ts*|*TS*)
                echo "$event"
                return 0
                ;;
        esac
    done

    return 1
}

case "${1:-info}" in

    info)

        echo
        echo "========================================"
        echo " HTC HD2 Touchscreen"
        echo "========================================"
        echo

        if [ ! -d /dev/input ]; then
            echo "[FAIL] /dev/input does not exist."
            exit 1
        fi

        FOUND=0

        for event in /dev/input/event*; do

            [ -e "$event" ] || continue

            FOUND=1

            NAME_FILE="/sys/class/input/$(basename "$event")/device/name"

            echo "$event"

            if [ -f "$NAME_FILE" ]; then
                echo "  Name: $(cat "$NAME_FILE" 2>/dev/null || true)"
            fi

            echo
        done

        if [ "$FOUND" -eq 0 ]; then
            echo "[FAIL] No input event devices found."
            exit 1
        fi

        TOUCH="$(find_touchscreen || true)"

        if [ -n "$TOUCH" ]; then
            echo "Detected touchscreen:"
            echo "  $TOUCH"
        else
            echo "No touchscreen name detected automatically."
            echo "Check the event devices above."
        fi

        ;;

    test)

        if ! command -v ts_test >/dev/null 2>&1; then
            echo "[FAIL] ts_test not installed."
            exit 1
        fi

        TOUCH="$(find_touchscreen || true)"

        if [ -z "$TOUCH" ]; then
            echo "[FAIL] Could not automatically detect touchscreen."
            echo
            echo "Try:"
            echo "  touchscreen info"
            echo
            exit 1
        fi

        echo "Using touchscreen: $TOUCH"

        export TSLIB_TSDEVICE="$TOUCH"

        exec ts_test
        ;;

    calibrate)

        if ! command -v ts_calibrate >/dev/null 2>&1; then
            echo "[FAIL] ts_calibrate not installed."
            exit 1
        fi

        TOUCH="$(find_touchscreen || true)"

        if [ -z "$TOUCH" ]; then
            echo "[FAIL] Could not automatically detect touchscreen."
            echo
            echo "Try:"
            echo "  touchscreen info"
            echo
            exit 1
        fi

        echo "Using touchscreen: $TOUCH"

        export TSLIB_TSDEVICE="$TOUCH"
        export TSLIB_CALIBFILE="/etc/pointercal"

        exec ts_calibrate
        ;;

    *)

        echo "Usage:"
        echo "  touchscreen info"
        echo "  touchscreen test"
        echo "  touchscreen calibrate"
        exit 1
        ;;

esac
EOF

chmod 755 "$ROOTFS/usr/local/bin/touchscreen"

###############################################################################
# X session
###############################################################################

cat > "$ROOTFS/root/.xinitrc" <<EOF
#!/bin/sh

export DISPLAY=$DISPLAY_NUM

xset s off
xset -dpms
xset s noblank

###############################################################################
# Fullscreen terminal
###############################################################################

xterm \
    -fullscreen \
    -fa "fixed" \
    -fs 12 \
    -geometry ${SCREEN_WIDTH}x${SCREEN_HEIGHT}+0+0 \
    &

XTERM_PID=\$!

sleep 1

###############################################################################
# Virtual touchscreen keyboard
###############################################################################

matchbox-keyboard \
    --geometry ${SCREEN_WIDTH}x${KEYBOARD_HEIGHT}+0+$((SCREEN_HEIGHT - KEYBOARD_HEIGHT)) \
    &

KEYBOARD_PID=\$!

###############################################################################
# Keep X session alive while terminal is alive.
###############################################################################

wait \$XTERM_PID

kill \$KEYBOARD_PID 2>/dev/null || true

exit 0
EOF

chmod 755 "$ROOTFS/root/.xinitrc"

###############################################################################
# GUI launcher
#
# This is designed to run from tty1.
###############################################################################

cat > "$ROOTFS/usr/local/bin/hd2-gui" <<EOF
#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin

DISPLAY="$DISPLAY_NUM"
VT="$X_VT"

export DISPLAY

mkdir -p /var/log

###############################################################################
# Do not launch if X is already running.
###############################################################################

if [ -S /tmp/.X11-unix/X0 ]; then
    exit 0
fi

###############################################################################
# Start X through startx.
#
# Since this script is executed by init on tty1, startx gets
# a real controlling VT instead of being started as a detached
# background daemon.
###############################################################################

exec startx /root/.xinitrc -- "\$DISPLAY" "\$VT" \
    >> /var/log/hd2-gui.log 2>&1
EOF

chmod 755 "$ROOTFS/usr/local/bin/hd2-gui"

###############################################################################
# GUI control command
###############################################################################

cat > "$ROOTFS/usr/local/bin/gui" <<'EOF'
#!/bin/sh

case "${1:-status}" in

    start)

        echo "Starting HTC HD2 GUI..."

        if [ -S /tmp/.X11-unix/X0 ]; then
            echo "GUI is already running."
            exit 0
        fi

        /usr/local/bin/hd2-gui &
        ;;

    stop)

        echo "Stopping HTC HD2 GUI..."

        killall matchbox-keyboard 2>/dev/null || true
        killall xterm 2>/dev/null || true
        killall Xorg 2>/dev/null || true
        ;;

    restart)

        "$0" stop
        sleep 2
        "$0" start
        ;;

    status)

        if [ -S /tmp/.X11-unix/X0 ]; then
            echo "HTC HD2 GUI: running"
            exit 0
        fi

        echo "HTC HD2 GUI: stopped"
        exit 1
        ;;

    *)

        echo "Usage:"
        echo "  gui start"
        echo "  gui stop"
        echo "  gui restart"
        echo "  gui status"
        exit 1
        ;;

esac
EOF

chmod 755 "$ROOTFS/usr/local/bin/gui"

###############################################################################
# Configure automatic GUI startup through /etc/inittab
###############################################################################

echo "==> Configuring automatic GUI startup on tty1"

if [ ! -f "$ROOTFS/etc/inittab" ]; then

    cat > "$ROOTFS/etc/inittab" <<'EOF'
id:2:initdefault:

si::sysinit:/etc/init.d/rcS

~~:S:wait:/sbin/sulogin

1:2345:respawn:/sbin/getty -L tty1 38400 linux
2:23:respawn:/sbin/getty -L tty2 38400 linux
3:23:respawn:/sbin/getty -L tty3 38400 linux
4:23:respawn:/sbin/getty -L tty4 38400 linux
EOF

fi

###############################################################################
# Remove existing tty1 getty line.
###############################################################################

sed -i \
    '/^[[:space:]]*1:[^:]*:respawn:.*getty.*tty1/d' \
    "$ROOTFS/etc/inittab"

###############################################################################
# Add GUI tty1 line.
###############################################################################

cat >> "$ROOTFS/etc/inittab" <<'EOF'

# HTC HD2 graphical terminal
1:2345:respawn:/usr/local/bin/hd2-gui

# HTC HD2 CLI fallback
2:2345:respawn:/sbin/getty -L tty2 38400 linux
EOF

###############################################################################
# Ensure tty3 and tty4 remain available.
###############################################################################

if ! grep -q '^3:2345:' "$ROOTFS/etc/inittab"; then
    cat >> "$ROOTFS/etc/inittab" <<'EOF'
3:2345:respawn:/sbin/getty -L tty3 38400 linux
EOF
fi

if ! grep -q '^4:2345:' "$ROOTFS/etc/inittab"; then
    cat >> "$ROOTFS/etc/inittab" <<'EOF'
4:2345:respawn:/sbin/getty -L tty4 38400 linux
EOF
fi

###############################################################################
# Verify important installed files
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
    "$ROOTFS/usr/local/bin/touchscreen"
    "$ROOTFS/usr/local/bin/gui"
    "$ROOTFS/usr/local/bin/hd2-gui"

    "$ROOTFS/etc/network/interfaces"
    "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

    "$ROOTFS/etc/init.d/hd2-network"
    "$ROOTFS/etc/init.d/ssh"

    "$ROOTFS/etc/ssh/sshd_config"

    "$ROOTFS/root/.xinitrc"

    "$ROOTFS/etc/X11/xorg.conf.d/10-htc-hd2.conf"
    "$ROOTFS/etc/ts.conf"
    "$ROOTFS/etc/inittab"
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
# Verify important commands
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

    /usr/bin/Xorg
    /usr/bin/startx
    /usr/bin/xterm

    /usr/bin/matchbox-keyboard

    /usr/bin/ts_calibrate
    /usr/bin/ts_test

    /usr/local/bin/wifi
    /usr/local/bin/netinfo
    /usr/local/bin/touchscreen
    /usr/local/bin/gui
    /usr/local/bin/hd2-gui
)

for file in "${IMPORTANT_COMMANDS[@]}"; do

    if [ -e "$ROOTFS$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[WARN] Missing: $file"
    fi

done

###############################################################################
# Verify script syntax
###############################################################################

echo
echo "==> Checking Wi-Fi CLI syntax"

chroot "$ROOTFS" \
    /bin/sh -n /usr/local/bin/wifi

echo "[ OK ] wifi script syntax"

echo
echo "==> Checking network service syntax"

chroot "$ROOTFS" \
    /bin/sh -n /etc/init.d/hd2-network

echo "[ OK ] hd2-network syntax"

echo
echo "==> Checking touchscreen helper syntax"

chroot "$ROOTFS" \
    /bin/sh -n /usr/local/bin/touchscreen

echo "[ OK ] touchscreen script syntax"

echo
echo "==> Checking GUI launcher syntax"

chroot "$ROOTFS" \
    /bin/sh -n /usr/local/bin/hd2-gui

echo "[ OK ] hd2-gui syntax"

echo
echo "==> Checking GUI command syntax"

chroot "$ROOTFS" \
    /bin/sh -n /usr/local/bin/gui

echo "[ OK ] gui command syntax"

echo
echo "==> Checking X session syntax"

chroot "$ROOTFS" \
    /bin/sh -n /root/.xinitrc

echo "[ OK ] .xinitrc syntax"

###############################################################################
# Verify inittab
###############################################################################

echo
echo "==> Checking inittab"

if grep -q '^1:2345:respawn:/usr/local/bin/hd2-gui' \
    "$ROOTFS/etc/inittab"; then

    echo "[ OK ] GUI configured on tty1"

else

    echo "[FAIL] GUI tty1 entry missing"
    exit 1
fi

if grep -q '^2:2345:respawn:/sbin/getty' \
    "$ROOTFS/etc/inittab"; then

    echo "[ OK ] CLI fallback configured on tty2"

else

    echo "[FAIL] tty2 CLI entry missing"
    exit 1
fi

###############################################################################
# Verify GUI packages
###############################################################################

echo
echo "==> Checking GUI packages"

GUI_PACKAGES=(
    xserver-xorg
    xserver-xorg-core
    xserver-xorg-video-fbdev
    xserver-xorg-input-evdev
    xinit
    xterm
    matchbox-keyboard
    libts-bin
)

for package in "${GUI_PACKAGES[@]}"; do

    if chroot "$ROOTFS" dpkg-query \
        -W \
        -f='${Status}' \
        "$package" 2>/dev/null \
        | grep -q "install ok installed"; then

        echo "[ OK ] $package"

    else

        echo "[FAIL] Package not installed: $package"
        exit 1
    fi

done

###############################################################################
# Architecture
###############################################################################

echo
echo "==> Verifying Debian architecture"

if [ -f "$ROOTFS/var/lib/dpkg/arch" ]; then
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

Kernel:
  Existing HTC HD2 kernel 2.6.32

Boot files:
  Existing startup.txt
  Existing zImage
  Existing initrd.gz

Display:
  Resolution target: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}
  X display: ${DISPLAY_NUM}
  X virtual terminal: ${X_VT}
  Framebuffer: /dev/fb0
  X video driver: fbdev
  X input driver: evdev

Touchscreen:
  Kernel input device: /dev/input/eventX
  Detection: automatic
  tslib tools: enabled
  Calibration command: touchscreen calibrate
  Test command: touchscreen test

GUI:
  Xorg
  xinit
  xterm
  matchbox-keyboard
  Fullscreen terminal
  Virtual touchscreen keyboard
  GUI auto-start: tty1

CLI:
  tty2
  tty3
  tty4
  SSH

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
  USB Ethernet gadget fallback
  Framebuffer Xorg
  evdev touchscreen
  tslib utilities
  Fullscreen xterm
  Virtual touchscreen keyboard
  GUI auto-start

SSH:
  Root password must be configured manually using passwd.

Rootfs builder:
  GitHub Actions
EOF

###############################################################################
# Final verification
###############################################################################

echo
echo "============================================================"
echo " Final rootfs verification"
echo "============================================================"
echo

FINAL_FILES=(
    "$ROOTFS/sbin/init"
    "$ROOTFS/usr/local/bin/wifi"
    "$ROOTFS/usr/local/bin/netinfo"
    "$ROOTFS/usr/local/bin/touchscreen"
    "$ROOTFS/usr/local/bin/gui"
    "$ROOTFS/usr/local/bin/hd2-gui"
    "$ROOTFS/etc/init.d/ssh"
    "$ROOTFS/etc/init.d/hd2-network"
    "$ROOTFS/root/.xinitrc"
    "$ROOTFS/etc/inittab"
    "$ROOTFS/etc/X11/xorg.conf.d/10-htc-hd2.conf"
    "$ROOTFS/etc/ts.conf"
    "$ROOTFS/etc/resolv.conf"
)

for file in "${FINAL_FILES[@]}"; do

    if [ -e "$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[FAIL] Missing: $file"
        exit 1
    fi

done

echo
echo "[ OK ] /sbin/init"
echo "[ OK ] Wi-Fi CLI"
echo "[ OK ] Network service"
echo "[ OK ] SSH"
echo "[ OK ] Xorg"
echo "[ OK ] fbdev"
echo "[ OK ] evdev touchscreen"
echo "[ OK ] tslib tools"
echo "[ OK ] xterm"
echo "[ OK ] matchbox-keyboard"
echo "[ OK ] GUI auto-start on tty1"
echo "[ OK ] CLI fallback on tty2"
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

echo "GUI:"
echo "  Xorg + fbdev"
echo "  xterm fullscreen"
echo "  evdev touchscreen"
echo "  matchbox-keyboard"
echo "  Auto-start: YES"
echo "  tty1: GUI"
echo "  tty2: CLI"
echo

echo "Touchscreen:"
echo "  touchscreen info"
echo "  touchscreen test"
echo "  touchscreen calibrate"
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

echo "GUI control:"
echo "  gui start"
echo "  gui stop"
echo "  gui restart"
echo "  gui status"
echo

echo "SSH:"
echo "  passwd"
echo "  service ssh start"
echo "  service ssh status"
echo

echo "USB Ethernet gadget:"
echo "  $USB_IP"
echo

echo "============================================================"
echo " Build successful"
echo "============================================================"