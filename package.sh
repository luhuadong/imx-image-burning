#!/bin/bash

TARGET=rootfs.tar.bz2

if [ -f ${TARGET} ]; then
    echo "rm ${TARGET}"
    rm ${TARGET}
fi

time tar jcvf ${TARGET} --exclude=usr/share/qt5/examples --exclude=opt/imx-gpu-sdk --exclude=opt/ltp --exclude=opt/viv_samples --exclude=package.sh ./*

md5sum ${TARGET}
mv ${TARGET} ../
echo "Finish!"
