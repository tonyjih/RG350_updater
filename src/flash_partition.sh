#!/bin/sh

NEW_START=32768
NEW_END=819200
NEW_SIZE=$((${NEW_END} - ${NEW_START}))

SYSTEM_IMAGE=${SYSTEM_MOUNTPOINT}/system.bin
KERNEL_DEST=${SYSTEM_MOUNTPOINT}/fs/vmlinuz.bin
ROOTFS_DEST=${SYSTEM_MOUNTPOINT}/fs/rootfs.squashfs
MODULES_FS_DEST=${SYSTEM_MOUNTPOINT}/fs/modules.squashfs

error_quit() {
	umount ${SYSTEM_IMAGE}
	rm ${SYSTEM_IMAGE}
	exit 1
}


# Create a 400 MiB tmpfs. It won't be a problem even if the available
# amount of RAM is < 400 MiB.
mount none -t tmpfs -o size=400M "$SYSTEM_MOUNTPOINT"

# Create a ~386 MiB sparse file, format it to FAT32
dd if=/dev/zero of="${SYSTEM_MOUNTPOINT}/system.bin" \
	bs=1b count=0 seek=${NEW_SIZE} >/dev/null 2>&1
mkfs.vfat -F32 "${SYSTEM_MOUNTPOINT}/system.bin"

# Mount it, and copy the OS inside
mkdir "${SYSTEM_MOUNTPOINT}/fs"
mount -o loop "${SYSTEM_MOUNTPOINT}/system.bin" "${SYSTEM_MOUNTPOINT}/fs"

if [ "$BAR" ] ; then
	echo 'Copying kernel... '
	$BAR -w 54 -0 ' ' -n -o "$KERNEL_DEST" "$KERNEL"

	echo 'Copying root filesystem...'
	$BAR -w 54 -0 ' ' -n -o "$ROOTFS_DEST" "$ROOTFS"

	echo 'Copying modules filesystem...'
	$BAR -w 54 -0 ' ' -n -o "$MODULES_FS_DEST" "$MODULES_FS"
else
	echo 'Copying kernel... '
	cp "$KERNEL" "$KERNEL_DEST"

	echo 'Copying root filesystem...'
	cp "$ROOTFS" "$ROOTFS_DEST"

	echo 'Copying modules filesystem...'
	cp "$MODULES_FS" "$MODULES_FS_DEST"
fi

cp "${KERNEL}.sha1" "${KERNEL_DEST}.sha1"
cp "${ROOTFS}.sha1" "${ROOTFS_DEST}.sha1"
cp "${MODULES_FS}.sha1" "${MODULES_FS_DEST}.sha1"

umount "${SYSTEM_MOUNTPOINT}/fs"

# Shrink the image
python trimfat.py "${SYSTEM_MOUNTPOINT}/system.bin"

# Flash the image!
echo ''
echo 'Flashing the new system partition. Please be patient.'
if [ "$BAR" ] ; then
	$BAR -w 54 -0 ' ' -n "${SYSTEM_MOUNTPOINT}/system.bin" | dd of=${SYSTEM_DEVICE} \
		bs=1b seek=${NEW_START} conv=notrunc 2>/dev/null
else
	dd if="${SYSTEM_MOUNTPOINT}/system.bin" of=${SYSTEM_DEVICE} \
		bs=1b seek=${NEW_START} conv=notrunc 2>/dev/null
fi

echo 'Flushing write cache... '
sync
umount "${SYSTEM_PARTITION}/fs"

echo 'Writing new partition table...'
echo ${NEW_START},${NEW_SIZE} | sfdisk --no-reread -uS -N \
	${SYSTEM_PART_NUM} ${SYSTEM_DEVICE}

echo 'Writing new bootloader...'
if [ -f "$BOOTLOADER" ] ; then
	dd if="$BOOTLOADER" of=${SYSTEM_DEVICE} bs=512 seek=1 \
		count=16 conv=notrunc 2>/dev/null
	sync
fi

dialog --msgbox 'Update complete!\nThe system will now restart.\n\n
If for some reason the system fails to boot, try to press the
following keys while powering on the device:\n
    -X to boot the last working kernel,\n
    -Y to boot the last working rootfs.\n\n
Note that pressing both keys during the power-on sequence will load the very
same Operating System (kernel + rootfs) you had before upgrading.' 16 0
reboot
