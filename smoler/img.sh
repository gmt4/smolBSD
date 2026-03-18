#!/bin/sh

OS=$(uname -s|tr 'A-Z' 'a-z')

case $OS in
linux|darwin) ;;
*)
	echo "unsupported platform"
	exit 1
	;;
esac

ARCH=$(uname -m | sed -e 's/x86_64/amd64/g')

PATH=${PATH}:bin

install_oras()
{
	command -v oras >/dev/null && return
	version=$(curl -s https://api.github.com/repos/oras-project/oras/releases/latest | jq -r '.tag_name')
	curl -fsSL "https://github.com/oras-project/oras/releases/download/${version}/oras_${version#v}_${OS}_${ARCH}.tar.gz" | \
		tar zxf - -C bin oras
}

pulsh_usage()
{
	if [ $# -lt 2 ]; then
		echo "usage: $1 <image>"
		exit 1
	fi
}

SMOLREPO=${SMOLREPO:-ghcr.io/netbsdfr/smolbsd}

case "$1" in
pull)
	pulsh_usage $@
	install_oras
	oras pull ${SMOLREPO}/$2
	;;
push)
	pulsh_usage $@
	install_oras
	ocimg=${2#*/}
	oras push ${SMOLREPO}/${ocimg%.img} \
		--artifact-type application/vnd.smolbsd.image \
		${2}:application/x-raw-disk-image
	;;
images)
	cols=$(tput cols 2>/dev/null) || cols=80
	imgname=$((cols / 3))
	rcols=$((imgname / 2))
	fmt="%-${imgname}s %-${rcols}s %${rcols}s\n"
	printf "\033[1m${fmt}\033[0m" IMAGE SIZE CREATED
	for img in images/*.img
	do
		[ -f "$img" ] || continue
		base="${img##*/}"
		base="${base%.img}"
		size=$(du -sh $img|cut -f1)
		# stat(1) is not portable *at all*
		ctime=$(ls -l $img| awk '{ printf "%s %s %s\n",$6,$7,$8 }')
		printf "$fmt" "$base" "$size" "$ctime"
	done
	;;
*)
	echo "Unknown command: $1"
	exit 1
	;;
esac
