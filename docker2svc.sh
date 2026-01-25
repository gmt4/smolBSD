#!/bin/sh

# Converts a basic Dockerfile to a smolBSD service

set -e

if [ $# -lt 1 ] || [ ! -f "$1" ]; then
	echo "usage: $0 <Dockerfile>"
	exit 1
fi

dockerfile=$1

TMPOPTS=$(mktemp options-XXXXXX.mk)
sed -n 's/LABEL \(.*=.*\)/\1/p' $dockerfile \
	>${TMPOPTS}

. ./${TMPOPTS}

export CHOUPI=y
. service/common/funcs
. service/common/choupi

if [ -z "$SERVICE" ];then
	echo "${ERROR} no service name, exiting"
	exit 1
fi
if ! command -v jq >/dev/null; then
	echo "${ERROR} missing jq"
	exit 1
fi

servicedir="service/${SERVICE}"

if [ -d "$servicedir" ]; then
	echo "${INFO} $SERVICE already exists, recreating"
	rm -rf "$servicedir" etc/${SERVICE}.conf
fi

for d in etc postinst
do
	mkdir -p ${servicedir}/${d}
done
postinst="${servicedir}/postinst/postinst.sh"
etcrc="${servicedir}/etc/rc"

mv ${TMPOPTS} ${servicedir}/options.mk

# setup the chroot for RUN executions
cat >$postinst<<_EOF
#!/bin/sh
if [ ! -f /BUILDIMG ]; then
	echo "${ERROR} NOT IN BUILDER IMAGE! EXITING"
	exit 1
fi
. ../service/common/funcs

rootdir=\$(pwd) # postinst is ran from fake root
cat >etc/profile<<_PROFILE
PATH=\$PATH:/sbin:/usr/sbin:/usr/pkg/bin:/usr/pkg/sbin
export PATH
_PROFILE
cp /etc/resolv.conf etc/
mkdir -p usr/pkg/etc/pkgin
echo "https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/\${ARCH}/\${PKGVERS}/All" \
	>usr/pkg/etc/pkgin/repositories.conf
rsynclite /etc/openssl/ \${rootdir}/etc/openssl
_EOF

cat >${etcrc}<<_EOF
#!/bin/sh

. /etc/include/basicrc

_EOF
echo "ADDPKGS=pkgin pkg_tarup pkg_install sqlite3" \
	>>${servicedir}/options.mk

USER=root

grep -v '^$' $dockerfile|while read key val
do
	case "$key" in
	FROM)
		case "$val" in
		*img)
			echo "FROMIMG=${val}" >> ${servicedir}/options.mk
			;;
		*)
			echo "SETS=${val}," | sed 's/,/\.${SETSEXT} /g' \
				>> ${servicedir}/options.mk
			;;
		esac
		;;
	ENV)
		echo "export $val" | tee -a "$etcrc" "$postinst" >/dev/null
		;;
	ARG)
		echo "export $val" >>"$postinst"
		;;
	RUN)
		echo "chroot . su ${USER} -c \"${val}\"" >>"$postinst"
		;;
	EXPOSE)
		portfrom=${val%:*}
		portto=${val#*:}
		echo "hostfwd=::${portfrom}-:${portto}" \
			>>etc/${SERVICE}.conf
		;;
	ADD|COPY)
		src=${val% *}
		dst=${val##* }
		while :; do
			case "$src" in
			--chown=*)
				chown=${src#*=} # foo:bar file1 file2
				src=${chown#* } # file1 file2
				chown=${chown%% *} # foo:bar
				;;
			--chmod=*)
				chmod=${src#*=}
				src=${chmod#* }
				chmod=${chmod%% *}
				;;
			*)
				break
				;;
			esac
		done
		case "$src" in
		http*://*)
			echo "ftp -o ${dst#/}/${src##*/} ${src}" >>"$postinst"
			;;
		*)
			echo "rsynclite ${src} ${dst#/}" >>"$postinst"
			;;
		esac

		[ -n "$chown" ] && \
			echo "[ -d \"${src#/}\" ] && \
				chroot . sh -c \"chown -R $chown ${dst}\" || \
				chroot . sh -c \"chown -R $chown ${dst}/${src##*/}\"" \
			>>"$postinst"
		[ -n "$chmod" ] && \
			echo "[ -d \"${src#/}\" ] && \
				chroot . sh -c \"chmod -R $chmod ${dst}\" || \
				chroot . sh -c \"chmod -R $chmod ${dst}/${src##*/}\"" \
			>>"$postinst"
		;;
	USER)
		echo "chroot . sh -c \"id ${val} >/dev/null 2>&1 || \
			(useradd -m ${val} && groupadd ${val})\"" \
			>>"$postinst"
		USER=${val}
		;;
	VOLUME)
		echo "share=${val}" >>etc/${SERVICE}.conf
		# avoid mount_9p warning
		[ "${val#/}" = "${val}" ] && val="/${val}"
		echo "MOUNT9P=${val}" >>"$etcrc"
		echo ". /etc/include/mount9p" >>"$etcrc"
		echo "mkdir -p ${val#/}" >>"$postinst"
		;;
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

cat >>${etcrc}<<_ETCRC

. /etc/include/shutdown
_ETCRC

echo "${CHECK} ${SERVICE} service files generated"
echo -n "${ARROW} press enter to build ${SERVICE} image or ^C to exit"
read dum

[ "$(uname -s)" = "NetBSD" ] && MAKE=make || MAKE=bmake

$MAKE SERVICE=${SERVICE} build
