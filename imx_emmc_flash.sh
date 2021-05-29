#!/bin/bash -e
#
# Burn uboot & kernel & rootfs in EMMC

Script_Ver="1.0.0"
Author_Mail=luhuadong@163.com

DATE=`date +%Y%m%d`
TIME=`date +%H%M%S`
LOG_FILE="/tmp/imx_emmc_flash_${DATE}_${TIME}.log"

# e.g. evk, k37x, ipc
BOARD=ipc
ROOTFS=rootfs.tar.bz2
KERNEL=Image
DTB=imx8mq-${BOARD}.dtb
UBOOT=flash.bin

DEFAULTBLK=/dev/mmcblk0
MOUNTPOINT=/media
FWDIR=${MOUNTPOINT}/firmwares
FWDIR=/opt/firmwares
PARTITION_TABLE=emmc_partition_table.txt

DISK=$2
if [ -z ${DISK} ]; then
    DISK=${DEFAULTBLK}
fi

#mount -t vfat /dev/mmcblk1p2 ${MOUNTPOINT}
#check_ok

TARGET_BOOT=/tmp/boot
TARGET_ROOT=/tmp/rootfs

ERROR_FLAG=0
W_CNT=0
E_CNT=0
C_CNT=0

Logging() {
    echo -e $1
    echo -e $1 >> ${LOG_FILE}
}

Info() {
    Logging "(I) $1"
}

Command() {
    Logging "(C) $1"
    C_CNT=`expr $C_CNT + 1`
}

Warning() {
    Logging "(W) $1"
    W_CNT=`expr $W_CNT + 1`
}

Error() {
    Logging "(E) $1"
    E_CNT=`expr $E_CNT + 1`
}

check_ok() {
    ret=$?
    if [ $ret != 0 ]; then
        echo FAILED!
        #echo 1 > /sys/class/gpio/gpio84/value
        #usleep 5000000
        #echo 0 > /sys/class/gpio/gpio84/value
        exit 1
    else 
        echo OK!
    fi
}

# Check files if exist
CheckFiles() {
    FWFILES="${UBOOT} ${KERNEL} ${DTB} ${ROOTFS}"
    for file in ${FWFILES}
    do
        if [ ! -f ${FWDIR}/${file} ]; then
            echo "${FWDIR}/${file} is not exist"
	    exit 1
        fi
done
}

# Delete disk partition
DeletePartition() {
    Info "Delete disk partition ..."

    Command "sfdisk --delete ${DISK}"
    sfdisk --delete ${DISK}
    sleep 3
}

# Create disk partition table
Partition() {
    Info "Create disk partition table ..."

    DeletePartition

    Command "sfdisk ${DISK} < ${FWDIR}/${PARTITION_TABLE}"
    sfdisk ${DISK} < ${FWDIR}/${PARTITION_TABLE}

    check_ok
    sync
    sleep 3
}

# Format eMMC partition
Format() {
    Info "Format eMMC partition ..."

    # Format /dev/mmcblk0p1
    Command "mkfs.vfat -n boot ${DISK}p1"
    mkfs.vfat -n boot ${DISK}p1
    check_ok

    # Format /dev/mmcblk0p2
    Command "mkfs.ext4 -F -L rootfs ${DISK}p2"
    mkfs.ext4 -F -L rootfs ${DISK}p2
    check_ok

    # Format /dev/mmcblk0p3
    Command "mkfs.ext4 -F -L recovery ${DISK}p3"
    mkfs.ext4 -F -L recovery ${DISK}p3
    check_ok

    # Format /dev/mmcblk0p5
    Command "mkfs.ext4 -F -L database ${DISK}p5"
    mkfs.ext4 -F -L database ${DISK}p5
    check_ok

    # Format /dev/mmcblk0p6
    Command "mkfs.ext4 -F ${DISK}p6"
    mkfs.ext4 -F ${DISK}p6
    check_ok

    sync
    sleep 3
}

# Mount
Mount() {
    Info "Mount disk ..."

    if [ ! -d ${TARGET_BOOT} ]; then
        Command "mkdir ${TARGET_BOOT}"
        mkdir ${TARGET_BOOT}
    fi

    if [ ! -d ${TARGET_ROOT} ]; then
        Command "mkdir ${TARGET_ROOT}"
        mkdir ${TARGET_ROOT}
    fi

    Command "mount -t vfat ${DISK}p1 ${TARGET_BOOT}"
    mount -t vfat ${DISK}p1 ${TARGET_BOOT}
    check_ok
    Command "mount -t ext4 ${DISK}p2 ${TARGET_ROOT}"
    mount -t ext4 ${DISK}p2 ${TARGET_ROOT}
    check_ok

    Command "mkdir -p ${TARGET_ROOT}/usr/recovery ${TARGET_ROOT}/usr/database ${TARGET_ROOT}/mnt"
    mkdir -p ${TARGET_ROOT}/usr/recovery ${TARGET_ROOT}/usr/database ${TARGET_ROOT}/mnt

    Command "mount -t ext4 ${DISK}p3 ${TARGET_ROOT}/usr/recovery"
    mount -t ext4 ${DISK}p3 ${TARGET_ROOT}/usr/recovery
    check_ok
    Command "mount -t ext4 ${DISK}p5 ${TARGET_ROOT}/usr/database"
    mount -t ext4 ${DISK}p5 ${TARGET_ROOT}/usr/database
    check_ok
    Command "mount -t ext4 ${DISK}p6 ${TARGET_ROOT}/mnt"
    mount -t ext4 ${DISK}p6 ${TARGET_ROOT}/mnt
    check_ok
}

Unmount() {
    Info "Try unmount partitions ..."
    for i in {10..1}
    do
        if [ -b ${DISK}p$i ]; then
            if grep -qs "${DISK}p$i" /proc/mounts; then
                Command "umount ${DISK}p$i"
                umount ${DISK}p$i
            fi
        fi
    done
    sleep 1
}

# Write kernel & dtb
UpdateKernel() {
    Info "Write kernel ..."
    Command "cp ${FWDIR}/${KERNEL} ${TARGET_BOOT} -f"
    cp ${FWDIR}/${KERNEL} ${TARGET_BOOT} -f
    check_ok
}

UpdateDTB() {
    Info "Write dtbs ..."
    Command "cp ${FWDIR}/${DTB} ${TARGET_BOOT} -f"
    cp ${FWDIR}/${DTB} ${TARGET_BOOT} -f
    check_ok
}

# Write rootfs
UpdateRootfs() {
    Info "Write rootfs ..."
    Command "tar -jxvf ${FWDIR}/${ROOTFS} -C ${TARGET_ROOT}"
    tar -jxvf ${FWDIR}/${ROOTFS} -C ${TARGET_ROOT}
    check_ok
}

# Write U-Boot
UpdateUBoot() {
    Info "Write U-Boot ..."
    echo 0 > /sys/block/mmcblk0boot0/force_ro 
    Command "Clean /dev/mmcblk0boot0 10M"
    dd if=/dev/zero of=/dev/mmcblk0boot0 bs=1k seek=33 count=2048
    check_ok
    dd if=${UBOOT} of=/dev/mmcblk0boot0 bs=1k seek=33
    check_ok
    echo 1 > /sys/block/mmcblk0boot0/force_ro
    mmc bootpart enable 1 1 ${DISK}
    sync
}

Chean() {
    if [ -f ${LOG_FILE} ]; then
        rm ${LOG_FILE}
    fi
    clear
}

CheckPermission() {
    Info "Check user permission >>"

    account=`whoami`
    if [ ${account} != "root" ]; then
        Info "${account}, you are NOT the supervisor."
        Error "The root permission is required to run this installer."

        echo "Permission denied."
        exit 1
    fi
}

if [ -z $1 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: $0 [options] [disk]"
    echo ""
    echo "OPTIONS"
    echo "  -u, --unmount      Unmount all file systems for the specified disk"
    echo "  -m, --mount        Mount all file systems for the specified disk"
    echo "  -p, --partition    Partition for the specified disk"
    echo "  -d, --delete       Delete all partitions for the specified disk"
    echo "  -a, --all          Burn eMMC and update all files"
    echo "  -h, --help         Display this help and exit"
    echo "  -v, --version      Output version information and exit"
    echo ""
    exit 0
elif [ "$1" == "-v" ] || [ "$1" == "--version" ]; then
    echo "Script Version: ${Script_Ver}"
    exit 0
elif [ "$1" == "-u" ] || [ "$1" == "--unmount" ]; then
    Unmount
elif [ "$1" == "-m" ] || [ "$1" == "--mount" ]; then
    Mount
elif [ "$1" == "-p" ] || [ "$1" == "--partition" ]; then
    Unmount
    Partition
    Unmount
    Format
    Mount
elif [ "$1" == "-d" ] || [ "$1" == "--delete" ]; then
    DeletePartition
elif [ "$1" == "-a" ] || [ "$1" == "--all" ]; then
    Chean
    Logging "(*) Bocon eMMC Update for i.MX8 Linux"
    Logging "(*) Script Version : ${Script_Ver}"
    Logging "(*) E-mail : ${Author_Mail}"
    Logging " "

    Logging "Welcome to i.MX8 eMMC flash tool ^_^ *\n"
    CheckPermission
    CheckFiles
    Logging "uboot  : ${UBOOT}"
    Logging "kernel : ${KERNEL}"
    Logging "dtb    : ${DTB}"
    Logging "rootfs : ${ROOTFS}\n"
    Logging "Target disk: ${DISK}"
    Unmount
    Partition
    Unmount
    Format
    Mount
    UpdateUBoot
    UpdateKernel
    UpdateDTB
    UpdateRootfs
fi

echo "Executive command: ${C_CNT}, Warning: ${W_CNT}, Error: ${E_CNT}."

if [ ${E_CNT} -eq 0 ]; then
	#UpdateVersionInfo
	Logging "(*) Update success!"
	echo "Update success, log file in ${LOG_FILE}"
	echo "Now you can reboot system!"
else
	Logging "(*) Update failed!"
	echo "Update failed, log file in ${LOG_FILE}"
fi

exit 0
