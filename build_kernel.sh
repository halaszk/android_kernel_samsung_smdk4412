#!/bin/bash

# location
export KERNELDIR=`readlink -f .`
export PARENT_DIR=`readlink -f ..`
export INITRAMFS_SOURCE=`readlink -f $KERNELDIR/../initramfs3`

# kernel
export ARCH=arm
export USE_SEC_FIPS_MODE=true
export KERNEL_CONFIG="halaszk_defconfig"

# build script
export USER=`whoami`
# gcc 4.7.3 (Linaro 13.02)
export CROSS_COMPILE=${KERNELDIR}/android-toolchain/bin/arm-eabi-
#export CROSS_COMPILE=$PARENT_DIR/android_prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin/arm-eabi-
#export CROSS_COMPILE=/home/halaszk/android_build/SGS2/kernel/Dorimanx-SG2-I9100-Kernel/linaro-12-android-toolchain/bin/arm-eabi-
#export CROSS_COMPILE=/usr/bin/arm-linux-gnueabihf-
if [ "${1}" != "" ];then
export KERNELDIR=`readlink -f ${1}`
fi

# Importing PATCH for GCC depend on GCC version.
GCCVERSION_OLD=`${CROSS_COMPILE}gcc --version | cut -d " " -f3 | cut -c3-5 | grep -iv "09" | grep -iv "ee" | grep -iv "en"`
GCCVERSION_NEW=`${CROSS_COMPILE}gcc --version | cut -d " " -f4 | cut -c1-3 | grep -iv "Fre" | grep -iv "sof" | grep -iv "for" | grep -iv "auc"`

if [ "a$GCCVERSION_OLD" == "a4.3" ]; then
        cp $KERNELDIR/arch/arm/boot/compressed/Makefile_old_gcc ${KERNELDIR}/arch/arm/boot/compressed/Makefile
        echo "GCC 4.3.X Compiler Detected, building"
elif [ "a$GCCVERSION_OLD" == "a4.4" ]; then
        cp ${KERNELDIR}/arch/arm/boot/compressed/Makefile_old_gcc ${KERNELDIR}/arch/arm/boot/compressed/Makefile
        echo "GCC 4.4.X Compiler Detected, building"
elif [ "a$GCCVERSION_OLD" == "a4.5" ]; then
        cp ${KERNELDIR}/arch/arm/boot/compressed/Makefile_old_gcc ${KERNELDIR}/arch/arm/boot/compressed/Makefile
        echo "GCC 4.5.X Compiler Detected, building"
elif [ "a$GCCVERSION_NEW" == "a4.6" ]; then
        cp ${KERNELDIR}/arch/arm/boot/compressed/Makefile_linaro ${KERNELDIR}/arch/arm/boot/compressed/Makefile
        echo "GCC 4.6.X Compiler Detected, building"
elif [ "a$GCCVERSION_NEW" == "a4.7" ]; then
        cp ${KERNELDIR}/arch/arm/boot/compressed/Makefile_linaro ${KERNELDIR}/arch/arm/boot/compressed/Makefile
        echo "GCC 4.7.X Compiler Detected, building"
else
        echo "Compiler not recognized! please fix the CUT function to match your compiler."
        exit 0
fi;


NAMBEROFCPUS=`grep 'processor' /proc/cpuinfo | wc -l`

INITRAMFS_TMP="/tmp/initramfs-source"

if [ ! -f ${KERNELDIR}/.config ]; then
        cp ${KERNELDIR}/arch/arm/configs/${KERNEL_CONFIG} .config
        make ${KERNEL_CONFIG}
fi;


. ${KERNELDIR}/.config

cd ${KERNELDIR}/
nice -n 10 make -j2 || exit 1

# remove previous zImage files
if [ -e ${KERNELDIR}/zImage ]; then
rm ${KERNELDIR}/zImage
fi;

if [ -e ${KERNELDIR}/arch/arm/boot/zImage ]; then
rm ${KERNELDIR}/arch/arm/boot/zImage
fi;

# remove all old modules before compile
cd ${KERNELDIR}

OLDMODULES=`find -name *.ko`
for i in $OLDMODULES; do
rm -f $i
done;

# clean initramfs old compile data
rm -f usr/initramfs_data.cpio
rm -f usr/initramfs_data.o
if [ $USER != "root" ]; then
make -j$NAMBEROFCPUS modules || exit 1
else
nice -n 10 make -j$NAMBEROFCPUS modules || exit 1
fi;
#remove previous ramfs files
rm -rf $INITRAMFS_TMP
rm -rf $INITRAMFS_TMP.cpio
rm -rf $INITRAMFS_TMP.cpio.gz
# copy initramfs files to tmp directory
cp -ax $INITRAMFS_SOURCE $INITRAMFS_TMP
# clear git repositories in initramfs
if [ -e $INITRAMFS_TMP/.git ]; then
rm -rf /tmp/initramfs-source/.git
fi;
# remove empty directory placeholders
find $INITRAMFS_TMP -name EMPTY_DIRECTORY -exec rm -rf {} \;
# remove mercurial repository
if [ -d $INITRAMFS_TMP/.hg ]; then
rm -rf $INITRAMFS_TMP/.hg
fi;

# copy modules into initramfs
mkdir -p $INITRAMFS/lib/modules
mkdir -p $INITRAMFS_TMP/lib/modules
#mv -f drivers/media/video/samsung/mali_r3p0_lsi/mali.ko drivers/media/video/samsung/mali_r3p0_lsi/mali_r3p0_lsi.ko
#mv -f drivers/net/wireless/bcmdhd.cm/dhd.ko drivers/net/wireless/bcmdhd.cm/dhd_cm.ko
find -name '*.ko' -exec cp -av {} $INITRAMFS_TMP/lib/modules/ \;
${CROSS_COMPILE}strip --strip-debug $INITRAMFS_TMP/lib/modules/*.ko
chmod 755 $INITRAMFS_TMP/lib/modules/*
${CROSS_COMPILE}strip --strip-unneeded $INITRAMFS_TMP/lib/modules/*
cd $INITRAMFS_TMP
find | fakeroot cpio -H newc -o > $INITRAMFS_TMP.cpio 2>/dev/null
ls -lh $INITRAMFS_TMP.cpio
gzip -9 $INITRAMFS_TMP.cpio
cd -

GETVER=`grep 'Devil-.*-V' .config | sed 's/.*".//g' | sed 's/-S.*//g'`
read -p "create new kernel Image LOGO with version & date (y/n)?";
if [ "$REPLY" == "y" ]; then
# create new image with version & date
convert -ordered-dither threshold,32,64,32 -pointsize 17 -fill white -draw "text 230,1080 \"${GETVER} [$(date "+%H:%M | %d.%m.%Y"| sed -e ' s/\"/\\\"/g' )]\"" ${INITRAMFS_TMP}/res/images/icon_clockwork.png ${INITRAMFS_TMP}/res/images/icon_clockwork.png;
optipng -o7 ${INITRAMFS_TMP}/res/images/icon_clockwork.png;
fi;
# make kernel
nice -n 10 make -j4 zImage || exit 1

./mkbootimg --kernel ${KERNELDIR}/arch/arm/boot/zImage --ramdisk $INITRAMFS_TMP.cpio.gz --board smdk4x12 --base 0x10000000 --pagesize 2048 --ramdiskaddr 0x11000000 -o ${KERNELDIR}/boot.img.pre

${KERNELDIR}/mkshbootimg.py ${KERNELDIR}/boot.img ${KERNELDIR}/boot.img.pre ${KERNELDIR}/payload.tar
rm -f ${KERNELDIR}/boot.img.pre

	# copy all needed to ready kernel folder.
cp ${KERNELDIR}/.config ${KERNELDIR}/arch/arm/configs/${KERNEL_CONFIG}
cp ${KERNELDIR}/.config ${KERNELDIR}/READY/
rm ${KERNELDIR}/READY/boot/zImage
rm ${KERNELDIR}/READY/Kernel_*
stat ${KERNELDIR}/boot.img
cp ${KERNELDIR}/boot.img /${KERNELDIR}/READY/boot/
cd ${KERNELDIR}/READY/
        zip -r Kernel_${GETVER}-`date +"[%H-%M]-[%d-%m]-JB-SGSIII-PWR-CORE"`.zip .
rm ${KERNELDIR}/boot.img
rm ${KERNELDIR}/READY/boot/boot.img
rm ${KERNELDIR}/READY/.config
                read -p "push kernel to ftp (y/n)?"
                if [ "$REPLY" == "y" ]; then
			echo "Uploading kernel to FTP server";
			mv ${KERNELDIR}/READY/Kernel_* ${KERNELDIR}/SGSIII/
			ncftpput -f /home/halaszk/login.cfg -V -R / ${KERNELDIR}/SGSIII/
			rm ${KERNELDIR}/SGSIII/Kernel_*
			echo "Uploading kernel to FTP server DONE";

                fi;

