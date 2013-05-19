#!/bin/sh

cd `dirname $0`

KERNEL=./vmlinuz.bin
ROOTFS=./rootfs.squashfs
DATE_FILE=./date.txt

KERNEL_PARTITION=/dev/mmcblk0p1
KERNEL_MOUNTPOINT=/mnt/_kernel_update
KERNEL_TMP_DEST=$KERNEL_MOUNTPOINT/kernel_update.bin
KERNEL_DEST=$KERNEL_MOUNTPOINT/vmlinuz.bin
KERNEL_BACKUP=$KERNEL_MOUNTPOINT/vmlinuz.bak

ROOTFS_MOUNTPOINT=/boot
ROOTFS_TMP_DEST=$ROOTFS_MOUNTPOINT/update_rootfs.bin
ROOTFS_DEST=$ROOTFS_MOUNTPOINT/update_r.bin
ROOTFS_BACKUP=$ROOTFS_MOUNTPOINT/rootfs.bin.old

error_quit() {
	rm -f "$KERNEL_TMP_DEST" "$ROOTFS_TMP_DEST" "$ROOTFS_DEST"
	if [ -d "$KERNEL_MOUNTPOINT" ] ; then
		umount "$KERNEL_MOUNTPOINT" 2>/dev/null
		rmdir "$KERNEL_MOUNTPOINT"
	fi
	exit 1
}

DISCLAIMER="\Zb\Z3NOTICE\Zn

While we carefully constructed this updater,
it is possible flaws in the updater or in
the updated OS could lead to \Zb\Z3data loss\Zn. We
recommend that you \Zb\Z3backup\Zn all valuable
personal data on your GCW Zero before you
perform the update.

Do you want to update now?"

UP_TO_DATE=no
BAR=`which bar`

if [ -f "$DATE_FILE" ] ; then
	DATE="`cat $DATE_FILE`"
	export DIALOGOPTS="--colors --backtitle \"OpenDingux update $DATE\""
fi

echo "screen_color = (RED,RED,ON)" > /tmp/dialog_err.rc

if [ -f "$KERNEL" ] ; then
	mkdir "$KERNEL_MOUNTPOINT"
	mount "$KERNEL_PARTITION" "$KERNEL_MOUNTPOINT"

	DATE_OLD=`date -r "$KERNEL_DEST"`
	DATE_NEW=`date -r "$KERNEL"`

	if [ "$DATE_OLD" = "$DATE_NEW" ] ; then
		UP_TO_DATE=yes
	fi
fi

if [ -f "$ROOTFS" -a "$UP_TO_DATE" = "yes" ] ; then
	DATE_OLD=`date -r "$ROOTFS_MOUNTPOINT/rootfs.bin"`
	DATE_NEW=`date -r "$ROOTFS"`

	if [ "$DATE_OLD" != "$DATE_NEW" ] ; then
		UP_TO_DATE=no
	fi
fi

if [ "$UP_TO_DATE" = "yes" ] ; then
	dialog --defaultno --yesno 'The system seems to be already up to date.\n\n
Do you really want to continue?' 10 30
	if [ $? -ne 0 ] ; then
		error_quit
	fi
fi

dialog --defaultno --yes-label 'Update' --no-label 'Cancel' --yesno "$DISCLAIMER" 15 48
if [ $? -eq 1 ] ; then
	error_quit
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

if [ -f "$ROOTFS" ] ; then
	echo 'Installing updated root filesystem... '

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o "$ROOTFS_TMP_DEST" "$ROOTFS"
	else
		cp "$ROOTFS" "$ROOTFS_TMP_DEST"
	fi

	if [ $? -ne 0 ] ; then
		DIALOGRC="/tmp/dialog_err.rc" \
			dialog --msgbox 'ERROR!\n\nUnable to update RootFS.\nDo you have enough space available?' 10 34
		error_quit
	fi

	sync
fi

if [ -f "$KERNEL" ] ; then
	echo 'Installing updated kernel... '

	if [ "$BAR" ] ; then
		$BAR -w 54 -0 ' ' -n -o "$KERNEL_TMP_DEST" "$KERNEL"
	else
		cp "$KERNEL" "$KERNEL_TMP_DEST"
	fi

	if [ $? -ne 0 ] ; then
		DIALOGRC="/tmp/dialog_err.rc" \
			dialog --msgbox 'ERROR!\n\nUnable to update kernel.' 8 34
		error_quit
	fi

	sync
fi

echo ''

if [ -f "$ROOTFS" ] ; then
	if [ -f "$ROOTFS.sha1" ] ; then
		echo 'Verifying updated root filesystem for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$ROOTFS" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$ROOTFS" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat $ROOTFS.sha1`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated RootFS is corrupted!' 9 34
			error_quit
		fi
	fi
fi

if [ -f "$KERNEL" ] ; then
	if [ -f "$KERNEL.sha1" ] ; then
		echo 'Verifying updated kernel for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$KERNEL" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$KERNEL" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat $KERNEL.sha1`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated kernel is corrupted!' 9 34
			error_quit
		fi
	fi
fi

if [ -f "$BOOTLOADER" ] ; then
	if [ -f "$BOOTLOADER.sha1" ] ; then
		echo 'Verifying updated bootloader for corruption...'
		if [ "$BAR" ] ; then
			SHA1=`$BAR -w 54 -0 ' ' -n "$BOOTLOADER" | sha1sum | cut -d' ' -f1`
		else
			SHA1=`sha1sum "$BOOTLOADER" | cut -d' ' -f1`
		fi

		if [ "$SHA1" != "`cat $BOOTLOADER.sha1`" ] ; then
			DIALOGRC="/tmp/dialog_err.rc" \
				dialog --msgbox 'ERROR!\n\nUpdated bootloader is corrupted!' 9 34
			error_quit
		fi
	fi
fi

echo ''
echo 'Commiting changes. Please wait...'

if [ -f "$ROOTFS" ] ; then
	# Synchronize the dates
	touch -d "`date -r "$ROOTFS" +'%F %T'`" "$ROOTFS_TMP_DEST"

	mv "$ROOTFS_TMP_DEST" "$ROOTFS_DEST"
	sync
fi

if [ -f "$KERNEL" ] ; then
	# Synchronize the dates
	touch -d "`date -r "$KERNEL" +'%F %T'`" "$KERNEL_TMP_DEST"

	# Don't create a backup if we are already running from the backup kernel,
	# so that no matter what, we'll still have a working kernel installed.
	if [ -z `cat /proc/cmdline |grep kernel_bak` ] ; then
		cp "$KERNEL_DEST" "$KERNEL_BACKUP"
	fi

	mv "$KERNEL_TMP_DEST" "$KERNEL_DEST"
	umount "$KERNEL_MOUNTPOINT"
	rmdir "$KERNEL_MOUNTPOINT"
fi

if [ -f "$BOOTLOADER" ] ; then
	dd if="$BOOTLOADER" of=/dev/mmcblk0 bs=512 seek=1 count=16 conv=notrunc 2>/dev/null
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
