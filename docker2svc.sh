#!/bin/sh

# Converts a basic Dockerfile to a smolBSD service

if [ $# -lt 1 ]; then
	echo "usage: $0 <Dockerfile>"
	exit 1
fi

dockerfile=$1

service=$(sed -n 's/LABEL service=//p' $dockerfile)
if [ -z "$service" ];then
	echo "no service name, exiting"
	exit 1
fi
if ! command -v jq >/dev/null; then
	echo "missing jq"
	exit 1
fi

servicedir="service/${service}"

if [ -d "$servicedir" ]; then
	echo "$service already exists, recreating"
	rm -rf "$servicedir" etc/${service}.conf
fi

for d in etc postinst
do
	mkdir -p ${servicedir}/${d}
done
postinst="${servicedir}/postinst/postinst.sh"
etcrc="${servicedir}/etc/rc"

# setup the chroot for RUN executions
cat >$postinst<<_EOF
#!/bin/sh
if [ ! -f /BUILDIMG ]; then
	echo "/!\ NOT IN BUILDER IMAGE! EXITING"
	exit 1
fi
rootdir=\$(pwd) # postinst is ran from fake root
cat >etc/profile<<_PROFILE
PATH=\$PATH:/sbin:/usr/sbin:/usr/pkg/bin:/usr/pkg/sbin
export PATH
_PROFILE
cp /etc/resolv.conf etc/
mkdir -p usr/pkg/etc/pkgin
echo "https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/\${ARCH}/\${PKGVERS}/All" \
	>usr/pkg/etc/pkgin/repositories.conf
(cd /etc/openssl/ && tar cf - .)|(cd \${rootdir}/etc/openssl && tar xf -)
_EOF

cat >${etcrc}<<_EOF
#!/bin/sh

. /etc/include/basicrc

_EOF
echo "ADDPKGS=pkgin pkg_tarup pkg_install sqlite3" \
	>${servicedir}/options.mk

USER=root

grep -v '^$' $dockerfile|while read key val
do
	case "$key" in
	ARG)
		echo "export $val" >>"$postinst"
		;;
	ENV)
		echo "export $val" >>"$etcrc"
		;;
	RUN)
		echo "chroot . su ${USER} -c \"${val}\"" >>$postinst
		;;
	EXPOSE)
		portfrom=${val%:*}
		portto=${val#*:}
		echo "hostfwd=::${portfrom}-:${portto}" \
			>>etc/${service}.conf
		;;
	COPY)
		src=${val% *}
		dst=${val#* }
		echo "cp -R ${src} ${dst#/}" >>"$postinst"
		;;
	USER) USER=${val};;
	WORKDIR)
		echo "cd ${val}" >>"$etcrc"
		;;
	CMD|ENTRYPOINT)
		echo "${val}" | \
			jq -r 'if length > 1 then join(" ") else .[0] end' \
			>>"${etcrc}"
		;;
	*)
	esac
done
