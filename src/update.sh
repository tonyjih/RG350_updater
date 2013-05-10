#!/bin/sh

cd `dirname $0`

KERNEL=./vmlinuz.bin
ROOTFS=./rootfs.squashfs
DATE_FILE=./date.txt

DISCLAIMER="\Zb\Z3NOTICE\Zn

While we carefully constructed this updater,
it is possible flaws in the updater or in
the updated OS could lead to \Zb\Z3data loss\Zn. We
recommend that you \Zb\Z3backup\Zn all valuable
personal data on your GCW Zero before you
perform the update.

Do you want to update now?"

KERNEL_PARTITION=/dev/mmcblk0p1

UP_TO_DATE=no
BAR=`which bar`

if [ -f "$DATE_FILE" ] ; then
	DATE="`cat $DATE_FILE`"
	export DIALOGOPTS="--colors --backtitle \"OpenDingux update $DATE\""
fi

echo "screen_color = (RED,RED,ON)" > /tmp/dialog_err.rc

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

if [ -f "$ROOTFS" -a "$UP_TO_DATE" = "yes" ] ; then
	DATE_OLD=`date -r /boot/rootfs.bin`
	DATE_NEW=`date -r "$ROOTFS"`

	if [ "$DATE_OLD" != "$DATE_NEW" ] ; then
		UP_TO_DATE=no
	fi
fi

if [ "$UP_TO_DATE" = "yes" ] ; then
	dialog --defaultno --yesno 'The system seems to be already up to date.\n\n
Do you really want to continue?' 10 30
	if [ $? -ne 0 ] ; then
		exit
	fi
fi

dialog --defaultno --yes-label 'Update' --no-label 'Cancel' --yesno "$DISCLAIMER" 15 48
if [ $? -eq 1 ] ; then
	exit
fi

clear
echo 'Update in progress - please be patient.'
echo

HWVARIANT="`cat /proc/cmdline |sed 's/.*hwvariant=\([a-z_0-9]\+\).*/\1/'`"

if [ -z "$HWVARIANT" ] ; then
	# Only old "Frankenzeros" can have a bootloader so old that
	# it doesn't pass the 'hwvariant' parameter to the kernel...
	HWVARIANT="v11_ddr2_256mb"
fi

BOOTLOADER="./ubiboot-$HWVARIANT.bin"

if [ -f "$BOOTLOADER" ] ; then
	if [ -f "ubiboot-$HWVARIANT-sha1.txt" ] ; then
		echo 'Verifying updated bootloader for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$BOOTLOADER" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$BOOTLOADER" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat ubiboot-$HWVARIANT-sha1.txt`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated bootloader is corrupted!' 9 34
			exit 1
		fi
	fi

	echo -n 'Installing updated boot loader... '
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=1 count=16 conv=notrunc
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=17 count=16 conv=notrunc
	sync
	echo 'done'
	echo ''
fi

if [ -f "$ROOTFS" ] ; then
	if [ -f "rootfs_sha1.txt" ] ; then
		echo 'Verifying updated root filesystem for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$ROOTFS" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$ROOTFS" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat rootfs_sha1.txt`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated RootFS is corrupted!' 9 34
			exit 1
		fi
	fi

	echo 'Installing updated root filesystem... '

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o /boot/update_rootfs.bin "$ROOTFS"
	else
		cp "$ROOTFS" /boot/update_rootfs.bin
	fi

	if [ $? -ne 0 ] ; then
		DIALOGRC="/tmp/dialog_err.rc" \
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
	if [ -f "kernel_sha1.txt" ] ; then
		echo 'Verifying updated kernel for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$KERNEL" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$KERNEL" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat kernel_sha1.txt`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated kernel is corrupted!' 9 34
			rm /boot/update_r.bin
			exit 1
		fi
	fi

	echo 'Installing updated kernel... '

	mkdir /mnt/_kernel_update
	mount $KERNEL_PARTITION /mnt/_kernel_update

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o /mnt/_kernel_update/update_kernel.bin "$KERNEL"
	else
		cp "$KERNEL" /mnt/_kernel_update/update_kernel.bin
	fi

	if [ $? -ne 0 ] ; then
		DIALOGRC="/tmp/dialog_err.rc" \
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

dialog --msgbox 'Update complete!\nThe system will now restart.\n\n
If for some reason the system fails to boot, try to press the
following keys while powering on the device:\n
    -X to boot the last working kernel,\n
    -Y to boot the last working rootfs.\n\n
Note that pressing both keys during the power-on sequence will load the very
same Operating System (kernel + rootfs) you had before upgrading.' 16 0
reboot
