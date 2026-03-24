#!/bin/sh

set -e

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
	printf "usage: %s <build|pull|push|images>\n" $0
	;;
*)
	echo "not implemented."
	;;

esac
