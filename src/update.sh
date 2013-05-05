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

UP_TO_DATE=no
BAR=`which bar`

if [ -f "$KERNEL" ] ; then
	mkdir /mnt/_kernel_update
	mount $KERNEL_PARTITION /mnt/_kernel_update

	DATE_OLD=`date -r /mnt/_kernel_update/vmlinuz.bin`
	DATE_NEW=`date -r "$KERNEL"`

	umount /mnt/_kernel_update
	rmdir /mnt/_kernel_update

	if [ "$DATE_OLD" = "$DATE_NEW" ] ; then
		UP_TO_DATE=yes
	fi
fi

if [ -f "$ROOTFS" ] ; then
	. /etc/os-release
	OLD_VERSION="$VERSION"

	. "$OS_INFO"
	if [ "$UP_TO_DATE" = "yes" -a "$VERSION" != "$OLD_VERSION" ] ; then
		UP_TO_DATE=no
		exit
	fi
fi

if [ "$UP_TO_DATE" = "yes" ] ; then
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
	echo 'Installing updated root filesystem... '

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o /boot/update_rootfs.bin "$ROOTFS"
	else
		cp "$ROOTFS" /boot/update_rootfs.bin
	fi

	if [ $? -ne 0 ] ; then
		dialog --msgbox 'ERROR!\n\nUnable to update RootFS.\nDo you have enough space available?' 10 34
		rm /boot/update_rootfs.bin
		exit 1
	fi

	# Synchronize the dates
	touch -d "`date -r "$ROOTFS" +'%F %T'`" /boot/update_rootfs.bin

	sync
	mv /boot/update_rootfs.bin /boot/update_r.bin
	sync
	echo 'done.'
	echo
fi

if [ -f "$KERNEL" ] ; then
	echo 'Installing updated kernel... '

	mkdir /mnt/_kernel_update
	mount $KERNEL_PARTITION /mnt/_kernel_update

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o /mnt/_kernel_update/update_kernel.bin "$KERNEL"
	else
		cp "$KERNEL" /mnt/_kernel_update/update_kernel.bin
	fi

	if [ $? -ne 0 ] ; then
		dialog --msgbox 'ERROR!\n\nUnable to update kernel.' 8 34
		rm /boot/update_r.bin
		rm /mnt/_kernel_update/update_kernel.bin
		umount /mnt/_kernel_update
		rmdir /mnt/_kernel_update
		exit 1
	fi

	# Synchronize the dates
	touch -d "`date -r "$KERNEL" +'%F %T'`" /mnt/_kernel_update/update_kernel.bin

	sync

	# Don't create a backup if we are already running from the backup kernel,
	# so that no matter what, we'll still have a working kernel installed.
	if [ -z `cat /proc/cmdline |grep kernel_bak` ] ; then
		cp /mnt/_kernel_update/vmlinuz.bin /mnt/_kernel_update/vmlinuz.bak
	fi

	mv /mnt/_kernel_update/update_kernel.bin /mnt/_kernel_update/vmlinuz.bin
	umount /mnt/_kernel_update
	rmdir /mnt/_kernel_update
	echo 'done.'
	echo
fi

if [ -f "$BOOTLOADER" ] ; then
	echo 'Installing updated boot loader... '
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=1 count=16 conv=notrunc
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=17 count=16 conv=notrunc
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
