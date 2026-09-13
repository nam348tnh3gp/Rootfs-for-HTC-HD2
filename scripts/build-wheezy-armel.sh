#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Debian 7 Wheezy ARMEL rootfs builder
# HTC HD2 / HTC Leo
#
# GUI:
#   Direct Xorg -> xterm fullscreen + matchbox-keyboard
#
# NO:
#   startx
#   xinit
#   .xinitrc
#
# tty1 = GUI
# tty2 = CLI
# tty3 = CLI
# tty4 = CLI
#
# Boot files are NOT modified:
#   startup.txt
#   zImage
#   initrd.gz
###############################################################################

OUTPUT_DIR="${OUTPUT_DIR:-$PWD/output}"
ROOTFS="$OUTPUT_DIR/rootfs"

ARCH="armel"
SUITE="wheezy"
MIRROR="http://archive.debian.org/debian"

WIFI_IFACE="wlan0"
USB_IFACE="usb0"
USB_IP="192.168.7.2"
USB_NETMASK="255.255.255.0"

DISPLAY_NUM=":0"
X_VT="vt1"

SCREEN_WIDTH="480"
SCREEN_HEIGHT="800"
KEYBOARD_HEIGHT="240"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

###############################################################################
# Root check
###############################################################################
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this script as root."
    echo "Example:"
    echo "  sudo ./build-wheezy-armel.sh"
    exit 1
fi

###############################################################################
# Required tools
###############################################################################
for cmd in \
    debootstrap \
    chroot \
    mount \
    umount \
    mountpoint \
    cp \
    sed \
    grep \
    find \
    ls
do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing command: $cmd"
        exit 1
    fi
done

if [ ! -x /usr/bin/qemu-arm-static ]; then
    echo "ERROR: /usr/bin/qemu-arm-static not found."
    echo "Install qemu-user-static first."
    exit 1
fi

###############################################################################
# Cleanup
###############################################################################
cleanup() {
    set +e
    for dir in run sys proc dev; do
        if mountpoint -q "$ROOTFS/$dir"; then
            umount -lf "$ROOTFS/$dir"
        fi
    done
}
trap cleanup EXIT

###############################################################################
# Prepare
###############################################################################
echo
echo "============================================================"
echo "  Debian 7 Wheezy ARMEL RootFS"
echo "  HTC HD2 / HTC Leo"
echo "============================================================"
echo

rm -rf "$OUTPUT_DIR"
mkdir -p "$ROOTFS"

###############################################################################
# Bootstrap
###############################################################################
echo "==> Running debootstrap..."
debootstrap \
    --arch="$ARCH" \
    --foreign \
    --no-check-gpg \
    "$SUITE" \
    "$ROOTFS" \
    "$MIRROR"

###############################################################################
# QEMU
###############################################################################
echo "==> Installing qemu-arm-static..."
cp /usr/bin/qemu-arm-static \
    "$ROOTFS/usr/bin/qemu-arm-static"

###############################################################################
# APT
###############################################################################
echo "==> Configuring Debian archive..."
mkdir -p "$ROOTFS/etc/apt/apt.conf.d"

cat > "$ROOTFS/etc/apt/sources.list" <<EOF
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
# DNS for build
###############################################################################
rm -f "$ROOTFS/etc/resolv.conf"
cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

###############################################################################
# Mount virtual filesystems
###############################################################################
echo "==> Mounting /dev..."
mount --bind /dev "$ROOTFS/dev"

echo "==> Mounting /proc..."
mount -t proc proc "$ROOTFS/proc"

echo "==> Mounting /sys..."
mount -t sysfs sysfs "$ROOTFS/sys"

echo "==> Mounting /run..."
mkdir -p "$ROOTFS/run"
mount --bind /run "$ROOTFS/run"

###############################################################################
# Debian second stage
###############################################################################
echo "==> Running debootstrap second stage..."
chroot "$ROOTFS" \
    /debootstrap/debootstrap \
    --second-stage

###############################################################################
# Disable service startup while building
###############################################################################
cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "$ROOTFS/usr/sbin/policy-rc.d"

###############################################################################
# Basic system
###############################################################################
echo "htc-hd2" > "$ROOTFS/etc/hostname"

cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1       localhost
127.0.1.1       htc-hd2
::1             localhost ip6-localhost ip6-loopback
EOF

cat > "$ROOTFS/etc/fstab" <<'EOF'
/dev/mmcblk0p2  /       auto    defaults,noatime        0 1
proc            /proc   proc    defaults                0 0
sysfs           /sys    sysfs   defaults                0 0
tmpfs           /tmp    tmpfs   defaults                0 0
EOF

###############################################################################
# Network interfaces
###############################################################################
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
# Install packages
###############################################################################
echo
echo "============================================================"
echo "  Installing packages"
echo "============================================================"
echo

chroot "$ROOTFS" /bin/bash <<'CHROOT'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANG=C

apt-get \
    -o Acquire::Check-Valid-Until=false \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    -o APT::Get::AllowUnauthenticated=true \
    update

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
    xterm \
    x11-xserver-utils \
    matchbox-keyboard \
    libts-bin

echo
echo "[ OK ] Packages installed"
CHROOT

###############################################################################
# Wi-Fi
###############################################################################
echo "==> Configuring Wi-Fi..."

mkdir -p "$ROOTFS/etc/wpa_supplicant"
mkdir -p "$ROOTFS/var/run/wpa_supplicant"
mkdir -p "$ROOTFS/usr/local/bin"

cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" <<'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=00
EOF
chmod 600 "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

cat > "$ROOTFS/usr/local/bin/wifi" <<'WIFI'
#!/bin/sh
IFACE="__WIFI_IFACE__"
CONF="/etc/wpa_supplicant/wpa_supplicant.conf"

case "${1:-help}" in

    on)
        ifconfig "$IFACE" up 2>/dev/null || ip link set "$IFACE" up 2>/dev/null || true
        ;;

    off)
        killall wpa_supplicant 2>/dev/null || true
        killall dhclient 2>/dev/null || true
        ifconfig "$IFACE" down 2>/dev/null || true
        ;;

    scan)
        ifconfig "$IFACE" up 2>/dev/null || true
        iwlist "$IFACE" scan
        ;;

    connect)
        SSID="${2:-}"
        if [ -z "$SSID" ]; then
            printf "SSID: "
            read -r SSID
        fi

        printf "Password: "
        stty -echo 2>/dev/null || true
        read -r PASSWORD
        stty echo 2>/dev/null || true
        echo

        killall wpa_supplicant 2>/dev/null || true
        killall dhclient 2>/dev/null || true

        ifconfig "$IFACE" up 2>/dev/null || \
            ip link set "$IFACE" up 2>/dev/null || true

        wpa_passphrase "$SSID" "$PASSWORD" > "$CONF"
        chmod 600 "$CONF"

        wpa_supplicant \
            -B \
            -D wext \
            -i "$IFACE" \
            -c "$CONF" 2>/dev/null || \
        wpa_supplicant \
            -B \
            -i "$IFACE" \
            -c "$CONF"

        sleep 5
        dhclient "$IFACE"

        echo
        echo "Wi-Fi connected."
        ip addr show "$IFACE"
        ;;

    test)
        echo "Interface:"
        ip addr show "$IFACE" 2>/dev/null || true

        echo
        echo "Wireless:"
        iwconfig "$IFACE" 2>/dev/null || true

        echo
        echo "Route:"
        ip route 2>/dev/null || route -n

        echo
        echo "Internet:"
        if ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
            echo "[ OK ] Internet"
        else
            echo "[FAIL] Internet"
        fi

        echo
        echo "DNS:"
        if getent hosts debian.org >/dev/null 2>&1; then
            echo "[ OK ] DNS"
        else
            echo "[FAIL] DNS"
        fi
        ;;

    *)
        echo "Usage:"
        echo
        echo "  wifi on"
        echo "  wifi off"
        echo "  wifi scan"
        echo "  wifi connect [SSID]"
        echo "  wifi test"
        ;;
esac
WIFI

sed -i "s|__WIFI_IFACE__|$WIFI_IFACE|g" "$ROOTFS/usr/local/bin/wifi"
chmod 755 "$ROOTFS/usr/local/bin/wifi"

###############################################################################
# SSH
###############################################################################
echo "==> Configuring SSH..."

if [ -f "$ROOTFS/etc/ssh/sshd_config" ]; then
    sed -i \
        's/^#*[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' \
        "$ROOTFS/etc/ssh/sshd_config"

    sed -i \
        's/^#*[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/' \
        "$ROOTFS/etc/ssh/sshd_config"

    grep -q '^PermitRootLogin' "$ROOTFS/etc/ssh/sshd_config" || \
        echo "PermitRootLogin yes" >> "$ROOTFS/etc/ssh/sshd_config"

    grep -q '^PasswordAuthentication' "$ROOTFS/etc/ssh/sshd_config" || \
        echo "PasswordAuthentication yes" >> "$ROOTFS/etc/ssh/sshd_config"
fi

chroot "$ROOTFS" update-rc.d ssh defaults || true
chroot "$ROOTFS" ssh-keygen -A || true

###############################################################################
# HTC HD2 network service
###############################################################################
echo "==> Creating hd2-network service..."

cat > "$ROOTFS/etc/init.d/hd2-network" <<'HD2NET'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          hd2-network
# Required-Start:    $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: HTC HD2 network initialization
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin
WIFI_IFACE="__WIFI_IFACE__"
USB_IFACE="__USB_IFACE__"
USB_IP="__USB_IP__"
USB_NETMASK="__USB_NETMASK__"

case "$1" in
    start)
        echo "==> HTC HD2 network"

        if ip link show "$WIFI_IFACE" >/dev/null 2>&1; then
            ifconfig "$WIFI_IFACE" up 2>/dev/null || true

            if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] && \
               grep -q '^network=' /etc/wpa_supplicant/wpa_supplicant.conf
            then
                wpa_supplicant \
                    -B \
                    -D wext \
                    -i "$WIFI_IFACE" \
                    -c /etc/wpa_supplicant/wpa_supplicant.conf \
                    2>/dev/null || \
                wpa_supplicant \
                    -B \
                    -i "$WIFI_IFACE" \
                    -c /etc/wpa_supplicant/wpa_supplicant.conf \
                    2>/dev/null || true

                sleep 5
                dhclient "$WIFI_IFACE" 2>/dev/null || true
            fi
        fi

        # USB Ethernet fallback
        modprobe g_ether 2>/dev/null || true
        sleep 1

        if ip link show "$USB_IFACE" >/dev/null 2>&1; then
            ifconfig "$USB_IFACE" \
                "$USB_IP" \
                netmask "$USB_NETMASK" \
                up 2>/dev/null || true
        fi
        ;;

    stop)
        killall dhclient 2>/dev/null || true
        killall wpa_supplicant 2>/dev/null || true
        ifconfig "$WIFI_IFACE" down 2>/dev/null || true
        ifconfig "$USB_IFACE" down 2>/dev/null || true
        ;;

    restart)
        "$0" stop
        sleep 1
        "$0" start
        ;;

    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
HD2NET

sed -i \
    -e "s|__WIFI_IFACE__|$WIFI_IFACE|g" \
    -e "s|__USB_IFACE__|$USB_IFACE|g" \
    -e "s|__USB_IP__|$USB_IP|g" \
    -e "s|__USB_NETMASK__|$USB_NETMASK|g" \
    "$ROOTFS/etc/init.d/hd2-network"

chmod 755 "$ROOTFS/etc/init.d/hd2-network"
chroot "$ROOTFS" update-rc.d hd2-network defaults || true

###############################################################################
# netinfo
###############################################################################
cat > "$ROOTFS/usr/local/bin/netinfo" <<'NETINFO'
#!/bin/sh
echo "========================================"
echo "  HTC HD2 Network"
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
NETINFO
chmod 755 "$ROOTFS/usr/local/bin/netinfo"

###############################################################################
# Xorg configuration
###############################################################################
echo
echo "============================================================"
echo "  Configuring Xorg"
echo "============================================================"
echo

mkdir -p "$ROOTFS/etc/X11/xorg.conf.d"
mkdir -p "$ROOTFS/tmp/.X11-unix"

cat > "$ROOTFS/etc/X11/xorg.conf.d/10-htc-hd2.conf" <<'XORG'
Section "ServerFlags"
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
EndSection

Section "Device"
    Identifier "HTC HD2 framebuffer"
    Driver     "fbdev"
    Option     "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier   "HTC HD2 Screen"
    Device       "HTC HD2 framebuffer"
    DefaultDepth 16
EndSection

Section "InputClass"
    Identifier          "HTC HD2 touchscreen"
    MatchIsTouchscreen  "on"
    Driver              "evdev"
EndSection
XORG

###############################################################################
# tslib
###############################################################################
cat > "$ROOTFS/etc/ts.conf" <<'TSCONF'
module_raw input
module linear
module dejitter
TSCONF

###############################################################################
# Touchscreen helper
###############################################################################
cat > "$ROOTFS/usr/local/bin/touchscreen" <<'TOUCH'
#!/bin/sh

find_touchscreen() {
    for event in /dev/input/event*; do
        [ -e "$event" ] || continue

        NAME_FILE="/sys/class/input/$(basename "$event")/device/name"
        [ -f "$NAME_FILE" ] || continue

        NAME="$(cat "$NAME_FILE" 2>/dev/null || true)"

        case "$NAME" in
            *touch*|*Touch*|*TOUCH*)
                echo "$event"
                return 0
                ;;
        esac
    done
    return 1
}

case "${1:-info}" in
    info)
        echo "========================================"
        echo "  HTC HD2 Touchscreen"
        echo "========================================"
        echo
        for event in /dev/input/event*; do
            [ -e "$event" ] || continue
            NAME_FILE="/sys/class/input/$(basename "$event")/device/name"
            echo "$event"
            if [ -f "$NAME_FILE" ]; then
                echo "  Name: $(cat "$NAME_FILE")"
            fi
            echo
        done
        ;;

    test)
        TOUCH="$(find_touchscreen || true)"
        if [ -z "$TOUCH" ]; then
            echo "[FAIL] Touchscreen not found."
            exit 1
        fi
        export TSLIB_TSDEVICE="$TOUCH"
        exec ts_test
        ;;

    calibrate)
        TOUCH="$(find_touchscreen || true)"
        if [ -z "$TOUCH" ]; then
            echo "[FAIL] Touchscreen not found."
            exit 1
        fi
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
TOUCH
chmod 755 "$ROOTFS/usr/local/bin/touchscreen"

###############################################################################
# DIRECT XORG GUI
###############################################################################
echo "==> Creating direct Xorg GUI launcher..."

cat > "$ROOTFS/usr/local/bin/hd2-gui" <<'HD2GUI'
#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

DISPLAY="__DISPLAY_NUM__"
VT="__X_VT__"
export DISPLAY

LOG="/var/log/hd2-gui.log"
mkdir -p /var/log
exec >>"$LOG" 2>&1

echo
echo "============================================================"
echo "  HTC HD2 GUI"
echo "  DIRECT XORG"
echo "============================================================"
echo "Date:    $(date)"
echo "DISPLAY: $DISPLAY"
echo "VT:      $VT"
trap 'sleep 3' EXIT

###############################################################################
# Framebuffer
###############################################################################
if [ ! -e /dev/fb0 ]; then
    echo "[FAIL] /dev/fb0 does not exist."
    echo "Kernel framebuffer is required."
    exit 1
fi
echo "[ OK ] /dev/fb0"

###############################################################################
# X11 socket
###############################################################################
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

###############################################################################
# Remove stale X socket
###############################################################################
if [ -S /tmp/.X11-unix/X0 ]; then
    if pidof Xorg >/dev/null 2>&1; then
        echo "[ OK ] Xorg already running."
        exit 0
    fi
    rm -f /tmp/.X11-unix/X0
fi

###############################################################################
# START XORG DIRECTLY
###############################################################################
echo "==> Starting Xorg..."
/usr/bin/Xorg \
    "$DISPLAY" \
    "$VT" \
    -config /etc/X11/xorg.conf.d/10-htc-hd2.conf \
    &
XORG_PID=$!
echo "Xorg PID: $XORG_PID"

###############################################################################
# Wait for X socket
###############################################################################
COUNT=0
while [ "$COUNT" -lt 30 ]; do
    if ! kill -0 "$XORG_PID" 2>/dev/null; then
        echo "[FAIL] Xorg exited."
        wait "$XORG_PID" 2>/dev/null || true
        exit 1
    fi
    if [ -S /tmp/.X11-unix/X0 ]; then
        echo "[ OK ] Xorg ready."
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ ! -S /tmp/.X11-unix/X0 ]; then
    echo "[FAIL] Xorg socket not created."
    kill "$XORG_PID" 2>/dev/null || true
    wait "$XORG_PID" 2>/dev/null || true
    exit 1
fi

###############################################################################
# Disable blanking
###############################################################################
if command -v xset >/dev/null 2>&1; then
    DISPLAY="$DISPLAY" xset s off      || true
    DISPLAY="$DISPLAY" xset -dpms      || true
    DISPLAY="$DISPLAY" xset s noblank  || true
fi

###############################################################################
# XTERM
###############################################################################
echo "==> Starting fullscreen xterm..."
DISPLAY="$DISPLAY" \
    /usr/bin/xterm \
    -fullscreen \
    -fa fixed \
    -fs 12 \
    &
XTERM_PID=$!
echo "xterm PID: $XTERM_PID"

###############################################################################
# MATCHBOX KEYBOARD
###############################################################################
echo "==> Starting matchbox-keyboard..."
DISPLAY="$DISPLAY" \
    /usr/bin/matchbox-keyboard \
    --geometry __SCREEN_WIDTH__x__KEYBOARD_HEIGHT__+0+$((__SCREEN_HEIGHT__ - __KEYBOARD_HEIGHT__)) \
    &
KEYBOARD_PID=$!
echo "keyboard PID: $KEYBOARD_PID"

###############################################################################
# KEEP GUI ALIVE
###############################################################################
while true; do
    if ! kill -0 "$XORG_PID" 2>/dev/null; then
        echo "[INFO] Xorg stopped."
        break
    fi
    if ! kill -0 "$XTERM_PID" 2>/dev/null; then
        echo "[INFO] xterm stopped."
        break
    fi
    sleep 2
done

###############################################################################
# CLEANUP
###############################################################################
echo "==> Stopping GUI..."
kill "$KEYBOARD_PID" 2>/dev/null || true
kill "$XTERM_PID"    2>/dev/null || true
kill "$XORG_PID"     2>/dev/null || true

wait "$KEYBOARD_PID" 2>/dev/null || true
wait "$XTERM_PID"    2>/dev/null || true
wait "$XORG_PID"     2>/dev/null || true

rm -f /tmp/.X11-unix/X0
echo "==> GUI stopped."
exit 0
HD2GUI

sed -i \
    -e "s|__DISPLAY_NUM__|$DISPLAY_NUM|g" \
    -e "s|__X_VT__|$X_VT|g" \
    -e "s|__SCREEN_WIDTH__|$SCREEN_WIDTH|g" \
    -e "s|__SCREEN_HEIGHT__|$SCREEN_HEIGHT|g" \
    -e "s|__KEYBOARD_HEIGHT__|$KEYBOARD_HEIGHT|g" \
    "$ROOTFS/usr/local/bin/hd2-gui"

chmod 755 "$ROOTFS/usr/local/bin/hd2-gui"

###############################################################################
# GUI control
###############################################################################
cat > "$ROOTFS/usr/local/bin/gui" <<'GUI'
#!/bin/sh
case "${1:-status}" in
    start)
        if [ -S /tmp/.X11-unix/X0 ]; then
            echo "GUI already running."
            exit 0
        fi
        /usr/local/bin/hd2-gui &
        ;;

    stop)
        killall matchbox-keyboard 2>/dev/null || true
        killall xterm             2>/dev/null || true
        killall Xorg              2>/dev/null || true
        ;;

    restart)
        "$0" stop
        sleep 2
        "$0" start
        ;;

    status)
        if [ -S /tmp/.X11-unix/X0 ]; then
            echo "GUI: running"
            exit 0
        fi
        echo "GUI: stopped"
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
GUI
chmod 755 "$ROOTFS/usr/local/bin/gui"

###############################################################################
# inittab
###############################################################################
echo "==> Configuring inittab..."

if [ ! -f "$ROOTFS/etc/inittab" ]; then
    cat > "$ROOTFS/etc/inittab" <<'EOF'
id:2:initdefault:
si::sysinit:/etc/init.d/rcS
EOF
fi

sed -i '/^[[:space:]]*1:.*getty.*tty1/d'   "$ROOTFS/etc/inittab"
sed -i '/^[[:space:]]*1:.*hd2-gui/d'       "$ROOTFS/etc/inittab"
sed -i '/^[[:space:]]*2:.*getty.*tty2/d'   "$ROOTFS/etc/inittab"
sed -i '/^[[:space:]]*3:.*getty.*tty3/d'   "$ROOTFS/etc/inittab"
sed -i '/^[[:space:]]*4:.*getty.*tty4/d'   "$ROOTFS/etc/inittab"

cat >> "$ROOTFS/etc/inittab" <<'EOF'

# HTC HD2 GUI - direct Xorg
1:2345:respawn:/usr/local/bin/hd2-gui

# CLI fallback
2:2345:respawn:/sbin/getty -L tty2 38400 linux
3:2345:respawn:/sbin/getty -L tty3 38400 linux
4:2345:respawn:/sbin/getty -L tty4 38400 linux
EOF

###############################################################################
# Verification
###############################################################################
echo
echo "============================================================"
echo "  Verifying"
echo "============================================================"
echo

FILES=(
    "$ROOTFS/sbin/init"
    "$ROOTFS/usr/local/bin/hd2-gui"
    "$ROOTFS/usr/local/bin/gui"
    "$ROOTFS/usr/local/bin/wifi"
    "$ROOTFS/usr/local/bin/netinfo"
    "$ROOTFS/usr/local/bin/touchscreen"
    "$ROOTFS/etc/init.d/hd2-network"
    "$ROOTFS/etc/inittab"
    "$ROOTFS/etc/X11/xorg.conf.d/10-htc-hd2.conf"
    "$ROOTFS/etc/ts.conf"
)

for file in "${FILES[@]}"; do
    if [ -e "$file" ]; then
        echo "[ OK ] $file"
    else
        echo "[FAIL] $file"
        exit 1
    fi
done

###############################################################################
# Verify GUI packages
###############################################################################
echo
echo "==> Checking GUI packages..."

GUI_PACKAGES=(
    xserver-xorg
    xserver-xorg-core
    xserver-xorg-video-fbdev
    xserver-xorg-input-evdev
    xterm
    x11-xserver-utils
    matchbox-keyboard
    libts-bin
)

for package in "${GUI_PACKAGES[@]}"; do
    if chroot "$ROOTFS" dpkg-query \
        -W \
        -f='${Status}' \
        "$package" 2>/dev/null | grep -q "install ok installed"
    then
        echo "[ OK ] $package"
    else
        echo "[FAIL] $package"
        exit 1
    fi
done

###############################################################################
# Verify NO xinit / startx
###############################################################################
echo
echo "==> Checking startx/xinit..."
echo

if chroot "$ROOTFS" dpkg-query \
    -W \
    -f='${Status}' \
    xinit 2>/dev/null | grep -q "install ok installed"
then
    echo "[FAIL] xinit package is installed!"
    exit 1
fi
echo "[ OK ] xinit package not installed"

if [ -e "$ROOTFS/usr/bin/xinit" ]; then
    echo "[FAIL] /usr/bin/xinit exists!"
    exit 1
fi
echo "[ OK ] /usr/bin/xinit absent"

if [ -e "$ROOTFS/usr/bin/startx" ]; then
    echo "[FAIL] /usr/bin/startx exists!"
    exit 1
fi
echo "[ OK ] /usr/bin/startx absent"

###############################################################################
# Check actual startx commands
###############################################################################
echo
echo "==> Searching for actual startx commands..."

STARTX_FOUND=0

for dir in \
    "$ROOTFS/etc/init.d" \
    "$ROOTFS/etc/default" \
    "$ROOTFS/etc/rcS.d" \
    "$ROOTFS/etc/rc0.d" \
    "$ROOTFS/etc/rc1.d" \
    "$ROOTFS/etc/rc2.d" \
    "$ROOTFS/etc/rc3.d" \
    "$ROOTFS/etc/rc4.d" \
    "$ROOTFS/etc/rc5.d" \
    "$ROOTFS/etc/rc6.d" \
    "$ROOTFS/etc" \
    "$ROOTFS/root" \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/usr/local/sbin"
do
    [ -d "$dir" ] || continue

    if grep -Rni \
        --binary-files=without-match \
        --exclude='Xsession' \
        --exclude='*.md' \
        --exclude='*.txt' \
        '^[[:space:]]*startx[[:space:]]' \
        "$dir" \
        2>/dev/null
    then
        STARTX_FOUND=1
    fi
done

if [ "$STARTX_FOUND" -ne 0 ]; then
    echo
    echo "[FAIL] Actual startx command found!"
    exit 1
fi
echo "[ OK ] No actual startx command found"

###############################################################################
# Check hd2-gui
###############################################################################
echo
echo "==> Checking hd2-gui..."

HD2_GUI="$ROOTFS/usr/local/bin/hd2-gui"

if [ ! -f "$HD2_GUI" ]; then
    echo "[FAIL] Missing:"
    echo "  $HD2_GUI"
    echo
    echo "Contents of /usr/local/bin:"
    ls -la "$ROOTFS/usr/local/bin" 2>/dev/null || true
    echo
    echo "ROOTFS:"
    echo "  $ROOTFS"
    exit 1
fi
echo "[ OK ] $HD2_GUI"

if ! grep -q '/usr/bin/Xorg' "$HD2_GUI"; then
    echo "[FAIL] hd2-gui does not launch Xorg!"
    exit 1
fi
echo "[ OK ] hd2-gui launches Xorg directly"

if grep -q 'startx' "$HD2_GUI"; then
    echo "[FAIL] hd2-gui contains startx!"
    exit 1
fi
echo "[ OK ] hd2-gui contains no startx"

if grep -q 'xinit' "$HD2_GUI"; then
    echo "[FAIL] hd2-gui contains xinit!"
    exit 1
fi
echo "[ OK ] hd2-gui contains no xinit"

###############################################################################
# Xorg verification
###############################################################################
echo
echo "==> Checking Xorg..."

if [ -x "$ROOTFS/usr/bin/Xorg" ]; then
    echo "[ OK ] /usr/bin/Xorg"
else
    echo "[FAIL] Xorg missing"
    exit 1
fi

if [ -e "$ROOTFS/usr/lib/xorg/modules/drivers/fbdev_drv.so" ]; then
    echo "[ OK ] fbdev driver"
else
    echo "[WARN] fbdev driver missing"
fi

if [ -e "$ROOTFS/usr/lib/xorg/modules/input/evdev_drv.so" ]; then
    echo "[ OK ] evdev driver"
else
    echo "[WARN] evdev driver missing"
fi

###############################################################################
# Shell syntax
###############################################################################
echo
echo "==> Checking shell scripts..."

for script in \
    /usr/local/bin/hd2-gui \
    /usr/local/bin/gui \
    /usr/local/bin/wifi \
    /usr/local/bin/netinfo \
    /usr/local/bin/touchscreen \
    /etc/init.d/hd2-network
do
    chroot "$ROOTFS" /bin/sh -n "$script"
    echo "[ OK ] $script"
done

###############################################################################
# Verify inittab
###############################################################################
echo
echo "==> Checking inittab..."

grep -q '^1:2345:respawn:/usr/local/bin/hd2-gui' "$ROOTFS/etc/inittab" || {
    echo "[FAIL] tty1 GUI entry missing"
    exit 1
}

grep -q '^2:2345:respawn:/sbin/getty' "$ROOTFS/etc/inittab" || {
    echo "[FAIL] tty2 entry missing"
    exit 1
}

grep -q '^3:2345:respawn:/sbin/getty' "$ROOTFS/etc/inittab" || {
    echo "[FAIL] tty3 entry missing"
    exit 1
}

grep -q '^4:2345:respawn:/sbin/getty' "$ROOTFS/etc/inittab" || {
    echo "[FAIL] tty4 entry missing"
    exit 1
}

echo "[ OK ] tty1 GUI"
echo "[ OK ] tty2 CLI"
echo "[ OK ] tty3 CLI"
echo "[ OK ] tty4 CLI"

###############################################################################
# Build info
###############################################################################
cat > "$ROOTFS/etc/htc-hd2-build-info" <<EOF
Target:         HTC HD2 / HTC Leo
Distribution:   Debian GNU/Linux 7 Wheezy
Architecture:   armel
Root:           /dev/mmcblk0p2
Init:           /sbin/init

GUI:            Direct Xorg
                DISPLAY=$DISPLAY_NUM
                VT=$X_VT
                fbdev
                evdev
                xterm fullscreen
                matchbox-keyboard

GUI startup:    tty1
CLI:            tty2 tty3 tty4

startx:         NOT USED
xinit:          NOT USED

Touchscreen:    evdev
                tslib

Network:        Wi-Fi
                SSH
                USB Ethernet gadget fallback

Existing boot files:
    startup.txt
    zImage
    initrd.gz

Those boot files are NOT modified by this script.
EOF

###############################################################################
# Clean build files
###############################################################################
echo
echo "==> Cleaning rootfs..."

rm -f "$ROOTFS/usr/bin/qemu-arm-static"
rm -f "$ROOTFS/usr/sbin/policy-rc.d"

rm -rf "$ROOTFS/var/cache/apt/"*
rm -rf "$ROOTFS/var/lib/apt/lists/"*
rm -rf "$ROOTFS/tmp/"*
rm -rf "$ROOTFS/var/tmp/"*

mkdir -p "$ROOTFS/tmp"
chmod 1777 "$ROOTFS/tmp"

###############################################################################
# Final DNS
###############################################################################
rm -f "$ROOTFS/etc/resolv.conf"
cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

###############################################################################
# Final cleanup
###############################################################################
cleanup
trap - EXIT

###############################################################################
# Result
###############################################################################
echo
echo "============================================================"
echo "  BUILD SUCCESS"
echo "============================================================"
echo
echo "Rootfs:"
echo "  $ROOTFS"
echo
echo "Architecture:"
echo "  ARMEL 32-bit"
echo
echo "Distribution:"
echo "  Debian 7 Wheezy"
echo
echo "Boot:"
echo "  MAGLDR"
echo
echo "GUI:"
echo "  tty1 -> direct Xorg"
echo "  Xorg :0"
echo "  xterm fullscreen"
echo "  matchbox-keyboard"
echo
echo "CLI:"
echo "  tty2"
echo "  tty3"
echo "  tty4"
echo
echo "NO startx"
echo "NO xinit"
echo "NO .xinitrc"
echo
echo "Boot files NOT modified:"
echo "  startup.txt"
echo "  zImage"
echo "  initrd.gz"
echo
echo "============================================================"