#!/bin/sh

cd `dirname $0`

KERNEL=./vmlinuz.bin
ROOTFS=./rootfs.squashfs
BOOTLOADER=./ubiboot.bin
OS_INFO=./os-release

DISCLAIMER="NOTICE

While we carefully constructed this updater,
it is possible flaws in the updater or in
the updated OS could lead to data loss. We
recommend that you backup all valuable
personal data on your GCW Zero before you
perform the update.

Do you want to update now?"

KERNEL_PARTITION=/dev/mmcblk0p1

. /etc/os-release
OLD_VERSION="$VERSION"

. "$OS_INFO"
if [ "$VERSION" = "$OLD_VERSION" ] ; then
	dialog --defaultno --yesno 'The system seems to be already up to date.\n\n
Do you really want to continue?' 10 30
	if [ $? -ne 0 ] ; then
		exit
	fi
fi

dialog --defaultno --yes-label 'Update' --no-label 'Cancel' --yesno "$DISCLAIMER" 19 48
if [ $? -eq 1 ] ; then
	exit
fi

clear
echo 'Update in progress - please be patient.'
echo

if [ -f "$ROOTFS" ] ; then
	echo -n 'Installing updated root filesystem... '

	cp "$ROOTFS" /boot/update_rootfs.bin
	if [ $? -ne 0 ] ; then
		dialog --msgbox 'ERROR!\n\nUnable to update RootFS.\nDo you have enough space available?' 10 34
		rm /boot/update_rootfs.bin
		exit 1
	fi

	sync
	mv /boot/update_rootfs.bin /boot/update_r.bin
	sync
	echo 'done'
fi

if [ -f "$KERNEL" ] ; then
	echo -n 'Installing updated kernel... '

	mkdir /mnt/_kernel_update
	mount $KERNEL_PARTITION /mnt/_kernel_update

	cp "$KERNEL" /mnt/_kernel_update/update_kernel.bin
	if [ $? -ne 0 ] ; then
		dialog --msgbox 'ERROR!\n\nUnable to update kernel.' 8 34
		rm /boot/update_r.bin
		rm /mnt/_kernel_update/update_kernel.bin
		umount /mnt/_kernel_update
		rmdir /mnt/_kernel_update
		exit 1
	fi

	sync

	# Don't create a backup if we are already running from the backup kernel,
	# so that no matter what, we'll still have a working kernel installed.
	if [ -z `cat /proc/cmdline |grep kernel_bak` ] ; then
		cp /mnt/_kernel_update/vmlinuz.bin /mnt/_kernel_update/vmlinuz.bak
	fi

	mv /mnt/_kernel_update/update_kernel.bin /mnt/_kernel_update/vmlinuz.bin
	umount /mnt/_kernel_update
	rmdir /mnt/_kernel_update
	echo 'done'
fi

if [ -f "$BOOTLOADER" ] ; then
	echo -n 'Installing updated boot loader... '
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=1 count=16 conv=notrunc
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=17 count=16 conv=notrunc
	sync
	echo 'done'
fi

dialog --msgbox 'Update complete!\nThe system will now restart.\n\n
If for some reason the system fails to boot, try to press the
following keys while powering on the device:\n
    -X to boot the last working kernel,\n
    -Y to boot the last working rootfs.\n\n
Note that pressing both keys during the power-on sequence will load the very
same Operating System (kernel + rootfs) you had before upgrading.' 16 0
reboot
