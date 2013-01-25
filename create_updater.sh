#!/bin/bash
set -e
umask 0022

# Start with a fresh output dir.
rm -rf output
mkdir output

# Get kernel metadata.
KERNEL=`realpath vmlinuz.bin`

# Get rootfs metadata.
ROOTFS=`realpath rootfs.squashfs`
unsquashfs -n -i -d output/unsquashed $ROOTFS /etc/os-release
DATE=`date -r output/unsquashed/etc/os-release +%Y-%m-%d`

# Report metadata.
echo
echo "=========================="
echo
echo "Kernel:            $KERNEL"
echo "Root file system:  $ROOTFS"
echo "  build date:      $DATE"
echo
echo "=========================="
echo

# Write metadata.
cat > output/default.gcw0.desktop <<EOF
[Desktop Entry]
Name=OS Update
Version=$DATE
Comment=OpenDingux Update $DATE
Exec=update.sh
Icon=opendingux
Terminal=true
Type=Application
StartupNotify=true
Categories=applications;
EOF
# TODO: Reinstate this:
# X-OD-Manual=CHANGELOG

# Copy kernel and rootfs to output dir.
# We want to support symlinks for the kernel and rootfs images and if no
# copy is made, specifying the symlink will include the symlink in the OPK
# and specifying the real path might use a different name than the update
# script expects.
cp $KERNEL output/vmlinuz.bin
cp $ROOTFS output/rootfs.squashfs
chmod a-x output/vmlinuz.bin

# Create OPK.
OPK_FILE=output/gcw0-update-$DATE.opk
mksquashfs \
	output/default.gcw0.desktop \
	src/opendingux.png \
	src/update.sh \
	output/unsquashed/etc/os-release \
	output/vmlinuz.bin \
	output/rootfs.squashfs \
	$OPK_FILE \
	-no-progress -noappend -comp gzip -all-root

echo
echo "=========================="
echo
echo "Updater OPK:       $OPK_FILE"
echo
