PORTNAME=	pihole-ftl
DISTVERSION=	6.8
PORTREVISION=	1
CATEGORIES=	dns
MASTER_SITES=	https://codeberg.org/FreedomNAS/pihole-ftl-freebsd/archive/
DISTNAME=	${FTL_COMMIT}
DIST_SUBDIR=	${PORTNAME}

MAINTAINER=	dev@freedomnas.io
COMMENT=	Pi-hole FTL, the DNS and DHCP engine with its API and web server
WWW=		https://codeberg.org/FreedomNAS/pihole-ftl-freebsd

LICENSE=	EUPL12

BUILD_DEPENDS=	xxd:sysutils/xxd
LIB_DEPENDS=	libgmp.so:math/gmp \
		libhogweed.so:security/nettle \
		libidn2.so:dns/libidn2 \
		libmbedtls.so:security/mbedtls4 \
		libunistring.so:devel/libunistring

USES=		cmake pkgconfig readline

FTL_COMMIT=	b69250d8d9f9b6f6e3bb6fd992b661a8d643e356

WRKSRC=		${WRKDIR}/pihole-ftl-freebsd

# A tarball carries no git metadata, so the version comes from here; it is
# read while building (src/gen_version.cmake), not only when configuring
FTL_ENV=	GIT_BRANCH=freebsd GIT_HASH=${FTL_COMMIT:C/^(.{8}).*/\1/} \
		GIT_VERSION=v${DISTVERSION} GIT_TAG=v${DISTVERSION} \
		GIT_DATE=2026-10-22 STATIC=false
CONFIGURE_ENV=	${FTL_ENV}
MAKE_ENV=	${FTL_ENV}
CMAKE_ARGS=	-DCMAKE_DISABLE_FIND_PACKAGE_DBus=ON

PLIST_FILES=	bin/pihole-FTL

# The binary ends in a checksum of itself (pihole-FTL verify): stripping it
# would break that
do-install:
	${INSTALL} -m 555 ${BUILD_WRKSRC}/pihole-FTL ${STAGEDIR}${PREFIX}/bin/pihole-FTL

.include <bsd.port.mk>
