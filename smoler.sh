#!/bin/sh

set -e

case $1 in
build)
	/bin/sh smoler/build.sh $@
	;;
push|pull|images)
	/bin/sh smoler/img.sh $@
	;;
"")
	printf "usage: %s <build|pull|push>\n" $0
	;;
*)
	echo "not implemented."
	;;

esac
