#!/bin/bash

if [ $# -ne 3 ]; then
    echo "usage: <kernel> <ramdisk> <image>"
    exit 1
fi

if [ -z "$EC2_CERT" ] ; then
    echo "EC2_CERT is not set (did your source eucarc?)"
    exit 2
fi

if [ -z "$EC2_ACCESS_KEY" ] ; then
    echo "EC2_ACCESS_KEY is not set (did your source eucarc?)"
    exit 3
fi

KERNEL=$1
RAMDISK=$2
IMAGE=$3

if [ ! -r $KERNEL ]; then
    echo "error: kernel is not readable"
    exit 4
fi

if [ ! -r $RAMDISK ]; then
    echo "error: ramdisk is not readable"
    exit 5
fi

if [ ! -r $IMAGE ]; then
    echo "error: image is not readable"
    exit 6
fi

TOOLS_PREFIX="euca" # for euca2ools, can be changed to 'ec2'
TS=`date +%s`

echo "bundling, uploading, and registering the kernel..."
DIR=`mktemp -d -p .`
BUKKIT=`echo $DIR | sed "s/\.\///" | sed "s/\.//"`
$TOOLS_PREFIX-bundle-image -r x86_64 -i $KERNEL -d $DIR --kernel true
MANIFEST=`echo $DIR/*.manifest.xml`
$TOOLS_PREFIX-upload-bundle -b $BUKKIT -m $MANIFEST
MANIFEST=`echo $DIR/*.manifest.xml | sed "s/\.\///" | sed "s/\.//"`
echo $MANIFEST
EKI=`$TOOLS_PREFIX-register $MANIFEST -n kernel-$TS | awk '{print $2}'`
echo $EKI
rm -rf $DIR

if ( ! echo "$EKI" | egrep -q '.ki-' ); then
    echo "error: could not determine EKI (bundle, upload, or register failed)"
    exit 1
fi

echo "bundling, uploading, and registering the ramdisk..."
DIR=`mktemp -d -p .`
BUKKIT=`echo $DIR | sed "s/\.\///" | sed "s/\.//"`
$TOOLS_PREFIX-bundle-image -r x86_64 -i $RAMDISK -d $DIR --ramdisk true
MANIFEST=`echo $DIR/*.manifest.xml`
$TOOLS_PREFIX-upload-bundle -b $BUKKIT -m $MANIFEST
MANIFEST=`echo $DIR/*.manifest.xml | sed "s/\.\///" | sed "s/\.//"`
echo $MANIFEST
ERI=`$TOOLS_PREFIX-register $MANIFEST -n ramdisk-$TS | awk '{print $2}'`
echo $ERI
rm -rf $DIR

if ( ! echo "$ERI" | egrep -q '.ri-' ); then
    echo "error: could not determine ERI (bundle, upload, or register failed)"
    exit 1
fi

echo "bundling, uploading, and registering the image..."
DIR=`mktemp -d -p .`
BUKKIT=`echo $DIR | sed "s/\.\///" | sed "s/\.//"`
$TOOLS_PREFIX-bundle-image -r x86_64 -i $IMAGE -d $DIR --kernel $EKI --ramdisk $ERI
MANIFEST=`echo $DIR/*.manifest.xml`
$TOOLS_PREFIX-upload-bundle -b $BUKKIT -m $MANIFEST
MANIFEST=`echo $DIR/*.manifest.xml | sed "s/\.\///" | sed "s/\.//"`
echo $MANIFEST
EMI=`$TOOLS_PREFIX-register $MANIFEST -n image-$TS | awk '{print $2}'`
echo $EMI
rm -rf $DIR

if ( ! echo "$EMI" | egrep -q '.mi-' ); then
    echo "error: could not determine EKI (bundle, upload, or register failed)"
    exit 1
fi

echo "budling successful: eki=$EKI eri=$ERI emi=$EMI"
exit 0
