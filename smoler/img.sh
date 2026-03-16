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
*)
	echo "Unknown command: $1"
	exit 1
	;;
esac
