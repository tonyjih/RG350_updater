#!/bin/bash
set -e
umask 0022

# Start with a fresh output dir.
rm -rf output
mkdir output

BOOTLOADER_VARIANTS="rg350"

for i in $BOOTLOADER_VARIANTS ; do
	if [ -e "ubiboot-$i.bin" ] ; then
		BOOT="`realpath ubiboot-$i.bin`"
		BOOTLOADERS="$BOOTLOADERS $BOOT"
		cp "$BOOT" "output/ubiboot-$i.bin"
	else
		BOOTLOADERS=""
		rm -f output/ubiboot-*.bin
		break
	fi
done

if [ -r "mininit-syspart" ] ; then
	MININIT=`realpath mininit-syspart`
fi

if [ -r "vmlinuz.bin" ] ; then
	KERNEL=`realpath vmlinuz.bin`
elif [ -r "uImage" ] ; then
	KERNEL=`realpath uImage`
elif [ -r "uzImage.bin" ] ; then
	KERNEL=`realpath uzImage.bin`
fi

# Get kernel metadata.
if [ "$KERNEL" ] ; then
	if [ ! -r "modules.squashfs" ] ; then
		echo "ERROR: no modules.squashfs file found"
		exit 1
	fi
	MODULES_FS=`realpath modules.squashfs`
fi

# Get rootfs metadata.
if [ -e "rootfs.squashfs" ] ; then
	ROOTFS=`realpath rootfs.squashfs`
fi

if [ "$KERNEL" -a "$ROOTFS" ] ; then
	if [ `date -r "$KERNEL" +%s` -gt `date -r "$ROOTFS" +%s` ] ; then
		DATE=`date -r "$KERNEL" +%F`
	else
		DATE=`date -r "$ROOTFS" +%F`
	fi
elif [ "$KERNEL" ] ; then
	DATE=`date -r "$KERNEL" +%F`
elif [ "$ROOTFS" ] ; then
	DATE=`date -r "$ROOTFS" +%F`
else
	echo "ERROR: No kernel or rootfs found."
	exit 1
fi

# Report metadata.
echo
echo "=========================="
echo
echo "Bootloaders:          $BOOTLOADERS"
echo "Mininit:              $MININIT"
echo "Kernel:               $KERNEL"
echo "Modules file system:  $MODULES_FS"
echo "Root file system:     $ROOTFS"
echo "  build date:         $DATE"
echo
echo "=========================="
echo

# Write metadata.
cat > output/default.gcw0.desktop <<EOF
[Desktop Entry]
Name=OS Update
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
if [ -e "$KERNEL" ] ; then
	cp -a $KERNEL output/vmlinuz.bin
	cp -a $MODULES_FS output/modules.squashfs
	KERNEL="output/vmlinuz.bin"
	MODULES_FS="output/modules.squashfs"
	chmod a-x "$KERNEL" "$MODULES_FS"

	echo -n "Calculating SHA1 sum of kernel... "
	sha1sum "$KERNEL" | cut -d' ' -f1 > "output/vmlinuz.bin.sha1"
	echo "done"

	echo -n "Calculating SHA1 sum of modules file-system... "
	sha1sum "$MODULES_FS" | cut -d' ' -f1 > "output/modules.squashfs.sha1"
	echo "done"

	KERNEL="$KERNEL output/vmlinuz.bin.sha1 $MODULES_FS output/modules.squashfs.sha1"
fi

if [ -e "$ROOTFS" ] ; then
	cp -a $ROOTFS output/rootfs.squashfs
	ROOTFS="output/rootfs.squashfs"

	echo -n "Calculating SHA1 sum of rootfs... "
	sha1sum "$ROOTFS" | cut -d' ' -f1 > "output/rootfs.squashfs.sha1"
	echo "done"

	ROOTFS="$ROOTFS output/rootfs.squashfs.sha1"
fi

if [ "$BOOTLOADERS" ] ; then
	echo -n "Calculating SHA1 sum of bootloaders... "

	BOOTLOADERS=""

	for i in $BOOTLOADER_VARIANTS ; do
		BOOT="output/ubiboot-$i.bin"
		SHA1="output/ubiboot-$i.bin.sha1"
		BOOTLOADERS="$BOOTLOADERS $BOOT $SHA1"

		sha1sum "$BOOT" | cut -d' ' -f1 > "$SHA1"
	done
	echo "done"
fi

if [ "$MININIT" ] ; then
	cp -a $MININIT output/mininit-syspart
	MININIT="output/mininit-syspart"

	echo -n "Calculating SHA1 sum of mininit-syspart... "
	sha1sum "$MININIT" | cut -d' ' -f1 > "output/mininit-syspart.sha1"
	echo "done"

	MININIT="$MININIT output/mininit-syspart.sha1"
fi

echo "$DATE" > output/date.txt

# Create OPK.
OPK_FILE=output/rg350-update-$DATE.opk
mksquashfs \
	output/default.gcw0.desktop \
	src/opendingux.png \
	src/update.sh \
	src/trimfat.py \
	src/flash_partition.sh \
	output/date.txt \
	$BOOTLOADERS \
	$MININIT \
	$KERNEL \
	$ROOTFS \
	$OPK_FILE \
	-no-progress -noappend -comp gzip -all-root

echo
echo "=========================="
echo
echo "Updater OPK:       $OPK_FILE"
echo
