#!/bin/sh

set -e

progname=${0##*/}

usage()
{
	cat 1>&2 << _USAGE_
Usage: $progname [-s service] [-m megabytes] [-i image] [-x set]
       [-k kernel] [-o] [-c URL]

	Create a root image
	-s service	service name, default "rescue"
	-r rootdir	hand crafted root directory to use
	-m megabytes	image size in megabytes, default 10
	-i image	image name, default rescue-[arch].img
	-x sets		list of NetBSD sets, default rescue.tgz
	-k kernel	kernel to copy in the image
	-c URL		URL to a script to execute as finalizer
	-o		read-only root filesystem
	-b		make image BIOS bootable
	-u		non-colorful output
_USAGE_
	exit 1
}

options="s:m:i:r:x:k:c:bouh"

[ -f tmp/build* ] && . tmp/build*

export CHOUPI=y

while getopts "$options" opt
do
	case $opt in
	s) svc="$OPTARG";;
	m) megs="$OPTARG";;
	i) img="$OPTARG";;
	r) rootdir="$OPTARG";;
	x) sets="$OPTARG";;
	k) kernel="$OPTARG";;
	c) curlsh="$OPTARG";;
	b) biosboot=y;;
	o) rofs=y;;
	u) CHOUPI="";;
	h) usage;;
	*) usage;;
	esac
done

export ARCH PKGVERS

arch=${ARCH:-"amd64"}

svc=${svc:-"rescue"}
megs=${megs:-"20"}
img=${img:-"rescue-${arch}.img"}
sets=${sets:-"rescue.tar.xz"}
rootdir=${rootdir:-}
kernel=${kernel:-}
curlsh=${curlsh:-}
rofs=${rofs:-}
ADDSETS=${ADDSETS:-}
ADDPKGS=${ADDPKGS:-}
SVCIMG=${SVCIMG:-}

OS=$(uname -s)
TAR=tar
FETCH=$(pwd)/scripts/fetch.sh

. service/common/funcs
. service/common/choupi

is_netbsd=
is_linux=
is_darwin=
is_openbsd=
is_freebsd=
is_unknown=

case $OS in
NetBSD|smolBSD)
	is_netbsd=1
	FETCH=ftp
	;;
Linux)
	is_linux=1
	# avoid sets and pkgs untar warnings
	TAR=bsdtar
	;;
Darwin)
	# might be supported in the future
	is_darwin=1;;
OpenBSD)
	is_openbsd=1;;
FreeBSD)
	is_freebsd=1;;
*)
	is_unknown=1;
esac

for tool in $TAR # add more if needed
do
	if ! command -v $tool >/dev/null; then
		echo "$tool missing"
		exit 1
	fi
done

export TAR FETCH

if [ -z "$is_netbsd" ]; then
	if [ -n "$MINIMIZE" ] || [ -f "service/${svc}/NETBSD_ONLY" ]; then
		printf "\nThis image must be built on NetBSD!\n"
		printf "Use the image builder instead: make SERVICE=$svc build\n"
		exit 1
	fi
fi

[ -n "$is_darwin" -o -n "$is_unknown" ] && \
	echo "${progname}: OS is not supported" && exit 1

if [ -n "$is_linux" ]; then
	u=M
else
	u=m
fi

# inherit from another image
if [ -n "$FROMIMG" ]; then
	echo "${ARROW} using ${FROMIMG} as base image"
	cp images/${FROMIMG} ${img}
else
	dd if=/dev/zero of=./${img} bs=1${u} count=${megs}
fi

mkdir -p mnt
mnt=$(pwd)/mnt

wedgename="${svc}root"

if [ -n "$is_linux" ]; then
	vnd=$(losetup -Pf --show ${img})
	sgdisk --zap-all ${vnd}
	sgdisk --new=1:0:0 --typecode=1:8300 --change-name=1:"$wedgename" ${vnd}
	[ -z "$FROMIMG" ] && mke2fs -O none ${vnd}p1
	mount ${vnd}p1 $mnt
	mountfs="ext2fs"
elif [ -n "$is_freebsd" ]; then
	vnd=$(mdconfig -l -f $img || mdconfig -f $img)
	[ -z "$FROMIMG" ] && newfs -o time -O1 -m0 /dev/${vnd}
	mount -o noatime /dev/${vnd} $mnt
	mountfs="ffs"
else # NetBSD, use wedges
	vnd=$(vndconfig -l|grep -m1 'not'|cut -f1 -d:)
	vndconfig $vnd $img
	mountfs="ffs"

	getwedge()
	{
		mountdev=$(dkctl ${1} listwedges|sed -n "s/\(dk.*\):\ ${wedgename}.*/\1/p")
		if [ -z "$mountdev" ]; then
			echo "${ERROR} no wedge, exiting"
			exit 1
		fi
		echo "$mountdev"
	}

	if [ -z "$FROMIMG" ]; then
		gpt create ${vnd}
		gpt add -a 512k -l "$wedgename" -t ${mountfs} ${vnd}
		eval $(gpt show ${vnd}|awk '/NetBSD/ {print "startblk="$1; print "blkcnt="$2}')
		dkctl ${vnd} makewedges
		mountdev=$(getwedge ${vnd})
		newfs -O1 -m0 /dev/${mountdev}
	else
		# existing image given as source
		mountdev=$(getwedge ${vnd})
	fi
	mount -o log,noatime /dev/${mountdev} $mnt
fi

# additional packages
for pkg in ${ADDPKGS}; do
	# case 1, artefacts created by the builder service
	# minimization of the image via sailor is requested
	# we need packages cleanly installed via pkgin
	if [ -f /tmp/usrpkg.tgz ]; then
		echo "${ARROW} unpacking minimal env for sailor"
		# needed to re-create packages with pkg_tarup
		tar xfp /tmp/usrpkg.tgz -C /
		pkgin -y in $ADDPKGS
		# exit the loop, packages have been installed cleanly
		break
	fi
	# case 2, no need for recorded, cleanly installed packages
	# simply untar them to LOCALBASE
	pkg="pkgs/${arch}/${pkg}.tgz"
	[ ! -f ${pkg} ] && continue
	eval $($TAR xfp $pkg -O +BUILD_INFO|grep ^LOCALBASE)
	echo -n "extracting $pkg to ${LOCALBASE}.. "
	mkdir -p ${mnt}/${LOCALBASE}
	$TAR xfp ${pkg} --exclude='+*' -C ${mnt}/${LOCALBASE} || exit 1
	echo done
done
# minimization of the image via sailor is requested
if [ -n "$MINIMIZE" ] && \
	[ -f service/${svc}/sailor.conf ] && \
	[ -d /var/db/pkgin ]; then
	echo "${ARROW} minimize image"
	rm -rf ${mnt}/var/db/pkg*
	cd sailor
	export TERM=vt220
	PKG_RCD_SCRIPTS=YES ./sailor.sh build ../service/${svc}/sailor.conf
	cd ..
# root fs is hand made
elif [ -n "$rootdir" ]; then
	$TAR cfp - -C "$rootdir" . | $TAR xfp - -C $mnt
# use sets and customizations in services/
else
	for s in ${sets} ${ADDSETS}
	do
		# don't prepend sets path if this is a full path
		case $s in */*) ;; *) s="sets/${arch}/${s}" ;; esac
		echo -n "extracting ${s}.. "
		$TAR xfp ${s} -C ${mnt}/ || exit 1
		echo done
	done

fi

# $rootdir can be relative, don't cd mnt yet
for d in sbin bin dev etc/include
do
	mkdir -p ${mnt}/$d
done

[ -n "$rofs" ] && mountopt="ro" || mountopt="rw"
if [ "$mountfs" = "ffs" ]; then
	mountopt="${mountopt},log,noatime"
	rootdev="NAME=${wedgename}"
else
	rootdev="ROOT.a"
fi
echo "${rootdev} / $mountfs $mountopt 1 1" > ${mnt}/etc/fstab

rsynclite service/${svc}/etc/ ${mnt}/etc/
rsynclite service/common/ ${mnt}/etc/include/
[ -d service/${svc}/packages ]  && \
	rsynclite service/${svc}/packages ${mnt}/

[ -n "$kernel" ] && cp -f $kernel ${mnt}/netbsd

cd $mnt

if [ "$svc" = "rescue" ]; then
	for b in init mount_ext2fs
	do
		ln -s /rescue/$b sbin/
	done
	ln -s /rescue/sh bin/
fi

# warning, postinst operations are done on the builder

[ -d ../service/${svc}/postinst ] && \
    for x in $(set +f; ls ../service/${svc}/postinst/*.sh)
	do
		# if SVCIMG variable exists, only process its script
		if [ -n "$SVCIMG" ]; then
			[ "${x##*/}" != "${SVCIMG}.sh" ] && continue
			echo "SVCIMG=$SVCIMG" > etc/svc
		fi
		echo "executing $x"
		[ -f $x ] && sh $x
	done

# we don't need to hack our way around MAKEDEV on NetBSD / builder
if [ -z "$is_netbsd" ]; then
	# newer NetBSD versions use tmpfs for /dev, sailor copies MAKEDEV from /dev
	# backup MAKEDEV so imgbuilder rc can copy it
	cp dev/MAKEDEV etc/
	# unionfs with ext2 leads to i/o error
	sed -i'' 's/-o union//g' dev/MAKEDEV
fi
# record wanted pkgsrc version
echo "PKGVERS=$PKGVERS" > etc/pkgvers

# proceed with caution
[ -n "$curlsh" ] && curl -sSL "$CURLSH" | /bin/sh

[ -n "$MINIMIZE" ] && \
	rm -rf var/db/pkgin # wipe pkgin cache and db

# QEMU fw_cfg mountpoint
mkdir -p var/qemufwcfg

cd ..

if [ -n "$biosboot" ]; then
	cp /usr/mdec/boot ${mnt}
	cat >${mnt}/boot.cfg<<EOF
timeout=0
consdev=${BIOSCONSOLE}
EOF
fi

disksize=$(du -s ${mnt}|cut -f1)
umount $mnt

if [ -n "$MINIMIZE" ]; then
	addspace=$(( ${MINIMIZE#*+} * 2048 ))
	[ $addspace -eq 0 ] && addspace=$((disksize / 10))
	disksize=$(echo "$disksize + $addspace"|bc) # give 10% MB more
	echo "${ARROW} resizing image to $((disksize / 2048))MB"
	resize_ffs -y -s ${disksize} /dev/${mountdev}
fi

[ -n "$is_freebsd" ] && mdconfig -d -u $vnd
[ -n "$is_linux" ] && losetup -d $vnd
if [ -n "$is_netbsd" ] || [ -n "$is_openbsd" ]; then
	if [ -n "$biosboot" ]; then
		gpt biosboot -i 1 ${vnd}
		installboot -v /dev/r${mountdev} /usr/mdec/bootxx_ffsv1
	fi

	vndconfig -u $vnd
fi

if [ -n "$MINIMIZE" ]; then
	echo "${ARROW} truncating image to new size"
	dd if=/dev/zero of=${img} bs=1 count=1 seek=$((${disksize} * 512))
fi
exit 0
