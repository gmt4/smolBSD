#!/bin/sh

set -e

progname=${0##*/}

case $1 in
build)
	/bin/sh smoler/build.sh $@
	;;
push|pull|images)
	/bin/sh smoler/img.sh $@
	;;
run)
	for arch in amd64 evbarm-aarch64
	do
		base=${2%-${arch}*}
	done
	if [ -f "etc/${base}.conf" ]; then
		params="-f etc/${base}.conf"
	elif [ -f "images/${2}.img" ]; then
		params="-i $2"
	else
		params="-h"
	fi
	shift; shift # move to arg 3
	/bin/sh startnb.sh $params $@
	;;
"")
	cat 1>&2 << _USAGE_
Usage:
	$progname build [-y] <path/to/Dockerfile>
	$progname pull <image>
	$progname push <image>
	$progname images
	$progname run <image> [startnb.sh flags]
_USAGE_
	;;
*)
	echo "not implemented."
	;;

esac
