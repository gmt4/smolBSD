UNAME_M!=	uname -m

.if !defined(ARCH)
.  if ${UNAME_M} == "x86_64" || ${UNAME_M} == "amd64"
ARCH=	amd64
.  elif ${UNAME_M} == "aarch64" || ${UNAME_M} == "arm64"
ARCH=	evbarm-aarch64
.  else
ARCH=	${UNAME_M}
.  endif
.endif

.-include "service/${SERVICE}/options.mk"
.-include "service/${SERVICE}/own.mk"

VERS?=		11
PKGVERS?=	11.0_2025Q3
# for an obscure reason, packages path use uname -m...
DIST?=		https://nycdn.netbsd.org/pub/NetBSD-daily/netbsd-${VERS}/latest/${ARCH}/binary
PKGSITE?=	https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/${UNAME_M}/${PKGVERS}/All
KDIST=		${DIST}
WHOAMI!=	whoami
USER!= 		id -un
GROUP!= 	id -gn
BUILDIMG=	build-${ARCH}.img
BUILDIMGURL=	https://github.com/NetBSDfr/smolBSD/releases/download/latest/${BUILDIMG}

SERVICE?=	${.TARGET}
# guest root filesystem will be read-only
.if defined(MOUNTRO) && ${MOUNTRO} == "y"
EXTRAS+=	-o
.endif

# variables to transfer to mkimg.sh
ENVVARS=	SERVICE=${SERVICE} \
		ARCH=${ARCH} \
		PKGVERS=${PKGVERS} \
		MOUNTRO=${MOUNTRO} \
		PKGSITE=${PKGSITE} \
		ADDPKGS="${ADDPKGS}" \
		MINIMIZE=${MINIMIZE}

.if ${WHOAMI} != "root"
SUDO!=		command -v doas >/dev/null && \
		echo '${ENVVARS} doas' || \
		echo 'sudo -E ${ENVVARS}'
.else
SUDO=		${ENVVARS}
.endif

SETSEXT=	tar.xz
SETSDIR=	sets/${ARCH}
PKGSDIR=	pkgs/${ARCH}

.if ${ARCH} == "evbarm-aarch64"
KERNEL=		netbsd-GENERIC64.img
LIVEIMGGZ=	https://nycdn.netbsd.org/pub/NetBSD-daily/HEAD/latest/evbarm-aarch64/binary/gzimg/arm64.img.gz
.elif ${ARCH} == "i386"
KERNEL=		netbsd-SMOL386
KDIST=		https://smolbsd.org/assets
SETSEXT=	tgz
.else
KERNEL=		netbsd-SMOL
KDIST=		https://smolbsd.org/assets
LIVEIMGGZ=	https://nycdn.netbsd.org/pub/NetBSD-daily/HEAD/latest/images/NetBSD-11.99.3-amd64-live.img.gz
.endif

LIVEIMG=	NetBSD-${ARCH}-live.img

# sets to fetch, defaults to base
SETS?=		base.${SETSEXT} etc.${SETSEXT}

.if ${UNAME_M} == "x86_64"
ROOTFS?=	-r ld0a
.else
# unknown / aarch64
ROOTFS?=	-r ld5a
.endif

# any BSD variant including MacOS
DDUNIT=		m
UNAME_S!=	uname
.if ${UNAME_S} == "Linux"
DDUNIT=		M
.endif
FETCH=		scripts/fetch.sh

# extra remote script
.if defined(CURLSH) && !empty(CURLSH)
EXTRAS+=	-c ${CURLSH}
.endif

# default memory amount for a guest
MEM?=		256
# default port redirect, gives network to the guest
PORT?=		::22022-:22

IMGSIZE?=	512

# QUIET: default to quiet mode with Q=@, use Q= for verbose
Q=@

ARROW="➡️"
CHECK="✅"

help:	# This help you are reading
	$Qgrep '^[a-z]\+:.*#' Makefile

kernfetch:
	$Qmkdir -p kernels
	$Qif [ ! -f kernels/${KERNEL} ]; then \
		echo "${ARROW} fetching kernel"; \
		if [ "${ARCH}" = "amd64" ] || [ "${ARCH}" = "i386" ]; then \
			${FETCH} -o kernels/${KERNEL} ${KDIST}/${KERNEL}; \
		else \
			curl -L -o- ${KDIST}/kernel/${KERNEL}.gz | \
				gzip -dc > kernels/${KERNEL}; \
		fi; \
	fi

setfetch:
	@[ -d ${SETSDIR} ] || mkdir -p ${SETSDIR}
	$Qfor s in ${SETS}; do \
		[ -f ${SETSDIR}/$${s} ] || \
		( \
			echo "${ARROW} fetching set $${s}"; \
			${FETCH} -o ${SETSDIR}/$${s} ${DIST}/sets/$${s}; \
		) \
	done

pkgfetch:
	@[ -d ${PKGSDIR} ] || mkdir -p ${PKGSDIR}
	$Qfor p in ${ADDPKGS};do \
		[ -f ${PKGSDIR}/$${p}* ] || \
		( \
			echo "${ARROW} fetching package $${p}"; \
			${FETCH} -o ${PKGSDIR}/$${p}.tgz ${PKGSITE}/$${p}*; \
		) \
	done

fetchall: kernfetch setfetch pkgfetch

base: fetchall
	$Qecho "${ARROW} creating root filesystem (${IMGSIZE}M)"
	$Q${SUDO} ./mkimg.sh -i ${SERVICE}-${ARCH}.img -s ${SERVICE} \
		-m ${IMGSIZE} -x "${SETS}" ${EXTRAS}
	$Q${SUDO} chown ${USER}:${GROUP} ${SERVICE}-${ARCH}.img
	$Qecho "${CHECK} image ready: ${SERVICE}-${ARCH}.img"

buildimg: fetchall
	$Qmkdir -p images
	$Qecho "${ARROW} building the builder image"
	$Q${MAKE} SERVICE=build base
	$Qmv -f build-${ARCH}.img images/

fetchimg: fetchall
	$Qmkdir -p images
	$Qecho "${ARROW} fetching builder image"
	$Qif [ ! -f images/${BUILDIMG} ]; then \
		curl -L -o- ${BUILDIMGURL}.xz | xz -dc > images/${BUILDIMG}; \
	fi

build: fetchall # Build an image (SERVICE=$SERVICE found in services/)
	$Qif [ ! -f images/${.TARGET}-${ARCH}.img ]; then \
		${MAKE} buildimg; \
	fi
	$Qmkdir -p tmp
	$Qrm -f tmp/build-*
	# save variables for sourcing in the build vm
	$Qecho "${ENVVARS}" | \
		sed -E 's/[[:blank:]]+([A-Z_]+)/\n\1/g;s/=[[:blank:]]*([^\n]+)/="\1"/g' > \
		tmp/build-${SERVICE}
	$Qecho "${ARROW} starting the builder microvm"
	$Q./startnb.sh -k kernels/${KERNEL} -i images/${.TARGET}-${ARCH}.img -c 2 -m 1024 \
		-p ${PORT} -w . -x "-pidfile qemu-${.TARGET}.pid" &
	# wait till the build is finished, guest removes the lock
	$Qwhile [ -f tmp/build-${SERVICE} ]; do sleep 0.2; done
	$Qecho "${ARROW} killing the builder microvm"
	$Qkill $$(cat qemu-${.TARGET}.pid)
	$Q${SUDO} chown ${USER}:${GROUP} ${SERVICE}-${ARCH}.img

live: kernfetch # Buld a live image
	$Qecho "fetching ${LIVEIMG}"
	[ -f ${LIVEIMG} ] || curl -L -o- ${LIVEIMGGZ}|gzip -dc > ${LIVEIMG}

rescue: # Build a rescue image
	${MAKE} SERVICE=rescue build
