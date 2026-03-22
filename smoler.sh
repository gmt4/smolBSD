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
	/bin/sh startnb.sh -i "$2"
	;;
"")
	printf "usage: %s <build|pull|push|images>\n" $0
	;;
*)
	echo "not implemented."
	;;

esac
