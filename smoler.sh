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
	[ -f "images/${2}.img" ] && params="-i $2" || params="-h"
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
