###############################################################################
# Verify NO startx / NO xinit
###############################################################################

echo
echo "==> Checking startx/xinit..."
echo

# xinit package must not be installed
if chroot "$ROOTFS" dpkg-query \
    -W \
    -f='${Status}' \
    xinit 2>/dev/null |
    grep -q "install ok installed"
then
    echo "[FAIL] xinit is installed!"
    exit 1
fi

echo "[ OK ] xinit package not installed"

# startx executable must not exist
if [ -e "$ROOTFS/usr/bin/startx" ]; then
    echo "[FAIL] /usr/bin/startx exists!"
    exit 1
fi

echo "[ OK ] /usr/bin/startx absent"

###############################################################################
# Search executable/configuration areas
###############################################################################

echo
echo "==> Searching rootfs for startx references..."

STARTX_FOUND=0

for dir in \
    "$ROOTFS/etc" \
    "$ROOTFS/root" \
    "$ROOTFS/usr/local/bin" \
    "$ROOTFS/usr/local/sbin" \
    "$ROOTFS/usr/sbin" \
    "$ROOTFS/etc/init.d"
do

    [ -d "$dir" ] || continue

    if grep -Rni \
        --binary-files=without-match \
        "startx" \
        "$dir" \
        2>/dev/null
    then
        STARTX_FOUND=1
    fi

done

if [ "$STARTX_FOUND" -ne 0 ]; then
    echo
    echo "[FAIL] startx reference detected in rootfs!"
    echo
    exit 1
fi

echo "[ OK ] No startx reference in system scripts/config"

###############################################################################
# Verify our GUI launcher
###############################################################################

echo
echo "==> Checking hd2-gui..."

if grep -q '/usr/bin/Xorg' \
    "$ROOTFS/usr/local/bin/hd2-gui"
then
    echo "[ OK ] hd2-gui launches Xorg directly"
else
    echo "[FAIL] hd2-gui does not launch Xorg!"
    exit 1
fi

if grep -q 'startx' \
    "$ROOTFS/usr/local/bin/hd2-gui"
then
    echo "[FAIL] hd2-gui contains startx!"
    exit 1
fi

echo "[ OK ] hd2-gui contains no startx"

if grep -q 'xinit' \
    "$ROOTFS/usr/local/bin/hd2-gui"
then
    echo "[FAIL] hd2-gui contains xinit!"
    exit 1
fi

echo "[ OK ] hd2-gui contains no xinit"