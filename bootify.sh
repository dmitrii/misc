#!/bin/bash
#
# example of constructing a bootable disk from scratch, 
# using either GRUB 1 or GRUB 2
#
 
# figure out the highest version of GRUB installed
grub_setup=`which grub-setup` # grub-setup is only present in grub v2
grub=`which grub` # grub is present in grub v1
grub_ver=unknown
if [ -x "$grub" ] ; then
    grub_ver=1
fi
if [ -x "$grub_setup" ] ; then
    grub_ver=2 # v2 supercedes v1 if both are present
fi
if [ $grub_ver == 'unknown' ] ; then
    echo "grub 1 or 2 cannot be found"
    exit 1;
fi
echo found grub $grub_ver
 
# prepare the disk and its partitions and mount them on loopback devices
disk=disk.img
disk_map_id=hda
disk_nod_id=hda
fs_type=ext3
offset_sectors=63
disk_size_sectors=40960
echo creating disk and root partition in $disk
dd if=/dev/zero of=$disk bs=512 count=$disk_size_sectors

disk_loop_dev=`losetup -f`
losetup $disk_loop_dev $disk
echo attached $disk to $disk_loop_dev
diff $disk $disk_loop_dev

echo "0 $disk_size_sectors linear $disk_loop_dev 0" | dmsetup create ${disk_map_id}
disk_map_dev=/dev/mapper/${disk_map_id}
if [ ! -e "$disk_map_dev" ] ; then
    echo "cannot find $disk_map_dev"
    exit 1;
fi
echo mapped $disk_loop_dev to $disk_map_dev
diff $disk_loop_dev $disk_map_dev

# using $disk_map_dev instead of $disk_loop_dev with parted may result in "Inconsistent filesystem structure" error at boot time
parted --script $disk_map_dev mklabel msdos
parted --script $disk_map_dev mkpart primary $fs_type ${offset_sectors}s 100%
root_map_dev=${disk_map_dev}p1
if [ ! -e "$root_map_dev" ] ; then
    echo "cannot find $root_map_dev"
    exit 1;
fi

function domknod {
    map=$1
    nod=$2
    maj=`ls --dereference -l $map | cut -d ' ' -f 5 | cut -d ',' -f 1`
    min=`ls --dereference -l $map | cut -d ' ' -f 6`
    echo "mknod $nod b $maj $min"
    mknod $nod b $maj $min
}

function unused {
    # (UNUSED) loop device for access to root
    root_loop_dev=`losetup -f`
    losetup -o $((${offset_sectors}*512)) $root_loop_dev $disk
    
    disk_nod_dev=/dev/${disk_nod_id}
    root_nod_dev=/dev/${disk_nod_id}1
    domknod ${disk_map_dev} ${disk_nod_dev}
    domknod ${root_map_dev} ${root_nod_dev}
    if [ ! -e "$root_nod_dev" ] ; then
        echo "cannot find $root_nod_dev"
        exit 1;
    fi
}

echo creating file system on root partition at $root_map_dev
mkfs.$fs_type $root_map_dev
mkdir mnt
mount $root_map_dev mnt
mkdir -p mnt/boot/grub
umount mnt
sync

DISK_MAP=`dmsetup table ${disk_map_id}`
ROOT_MAP=`dmsetup table ${disk_map_id}p1`
dmsetup remove ${disk_map_id}p1
dmsetup remove ${disk_map_id}
echo "$DISK_MAP" | dmsetup create ${disk_map_id}
echo "$ROOT_MAP" | dmsetup create ${disk_map_id}1
root_map_dev=${disk_map_dev}1

echo resting...
sleep 5

mount $root_map_dev mnt
# run GRUB over the disk and root partition, either version 1 or 2
if [ $grub_ver == '1' ] ; then
    root_part=0 # 0 works with v1, but 1 works with v2
    echo creating grub 1 config...
    cfg=mnt/boot/grub/grub.conf
    echo "default=0" >$cfg
    echo "timeout=5" >>$cfg
    echo "title TheOS" >>$cfg
    echo "root (hd0,$root_part)" >>$cfg
    echo "kernel /boot/vmlinuz root=/dev/sda1 ro" >>$cfg
    echo "initrd /boot/initrd" >>$cfg
    cp $cfg mnt/boot/grub/menu.lst # some like grub.conf, some menu.lst
    cat $cfg
    sync

#    map=mnt/boot/grub/device.map
#    echo "(hd0) $disk_nod_dev" >$map
#    echo "created device.map:"
#    cat $map
 
#    echo copying grub 1 files and installing grub...
#    echo "grub-install --root-directory=mnt --no-floppy $disk_nod_dev"
#    grub-install --root-directory=mnt --no-floppy $disk_nod_dev

     echo copying grub 1 stage files...
#     cp /boot/grub/*stage* mnt/boot/grub
     cp /usr/lib/grub/x86_64-pc/*stage* mnt/boot/grub

    echo installing grub...
    (echo "device (hd0) $disk_map_dev"
        echo "root (hd0,$root_part)"
        echo "setup (hd0)"
        echo "quit"
	) | grub --batch

elif [ $grub_ver == '2' ] ; then
    # on Ubuntu 10.10 system 'msdos1' works
    # on Ubuntu 10.04.01 LTS system '1' works
    root_part=msdos1

    echo creating grub 2 config...
    cfg=mnt/boot/grub/grub.cfg
    echo "set default=0" >$cfg
    echo "set timeout=5" >>$cfg
    echo "insmod part_msdos" >>$cfg
    echo "insmod ext2" >>$cfg
    echo "set root='(hd0,$root_part)'" >>$cfg 
    echo "menuentry 'TheOS' --class os {" >>$cfg
    echo "  linux   /boot/vmlinuz ro max_loop=256" >>$cfg
    echo "  initrd  /boot/initrd " >>$cfg
    echo "}" >>$cfg
    sync

    echo copying grub 2 files and installing grub...
    grub-install --modules='part_msdos ext2' --root-directory=mnt '(hd0)'
    # also works on some systems:
#    grub-install --modules='part_msdos ext2' --root-directory=mnt $disk_loop_dev
fi
 
cp `ls -1 /boot/vmlinuz-* | tail -1` mnt/boot/vmlinuz
cp `ls -1 /boot/initrd.img-* | tail -1` mnt/boot/initrd
umount mnt
rmdir mnt
##losetup -d $root_loop_dev
##rm $root_nod_dev
##rm $disk_nod_dev
dmsetup remove ${disk_map_id}1
dmsetup remove ${disk_map_id}
losetup -d $disk_loop_dev
sync

echo "disk is ready, try:"
tput bold
echo kvm -nographic -curses $disk
tput sgr0
exit 0;
