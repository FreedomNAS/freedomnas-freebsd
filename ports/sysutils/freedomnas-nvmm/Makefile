PORTNAME=	freedomnas-nvmm
DISTVERSIONPREFIX=	v
DISTVERSION=	0.1.0
CATEGORIES=	sysutils

MAINTAINER=	dev@freedomnas.io
COMMENT=	NVMM hypervisor: kernel module, libnvmm and nvmmctl
WWW=		https://github.com/FreedomNAS/freebsd-nvmm

LICENSE=	BSD2CLAUSE

ONLY_FOR_ARCHS=	amd64

USES=		kmod uidfix
USE_GITHUB=	yes
GH_ACCOUNT=	FreedomNAS
GH_PROJECT=	freebsd-nvmm

GROUPS=		nvmm
GID_FILES=	${FILESDIR}/GIDs

MAKE_ARGS+=	WITHOUT_DEBUG_FILES=yes

do-build:
	${DO_MAKE_BUILD} -C ${WRKSRC}/sys/modules/nvmm
	${DO_MAKE_BUILD} -C ${WRKSRC}

do-install:
	${MKDIR} ${STAGEDIR}${KMODDIR} ${STAGEDIR}/usr/lib ${STAGEDIR}/usr/include \
	    ${STAGEDIR}/usr/sbin ${STAGEDIR}/usr/share/man/man3 \
	    ${STAGEDIR}/usr/share/man/man8 ${STAGEDIR}/usr/tests/lib
	${MAKE_CMD} -C ${WRKSRC}/sys/modules/nvmm ${MAKE_ARGS} DESTDIR=${STAGEDIR} install
	${MAKE_CMD} -C ${WRKSRC} ${MAKE_ARGS} DESTDIR=${STAGEDIR} install
	${RM} ${STAGEDIR}${KMODDIR}/linker.hints

.include <bsd.port.mk>
