#!/bin/sh

mkdir -p usr/pkg/etc/pkgin
echo "https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/${ARCH}/${PKGVERS}/All" > \
	usr/pkg/etc/pkgin/repositories.conf

touch BUILDIMG
mkdir drive2
# mkimg searches for ../service
ln -sf /mnt/service .
