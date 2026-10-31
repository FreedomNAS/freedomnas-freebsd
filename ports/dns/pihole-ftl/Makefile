PORTNAME=	pihole-ftl
DISTVERSION=	6.8
DISTVERSIONPREFIX=	v
PORTREVISION=	3
CATEGORIES=	dns
DIST_SUBDIR=	${PORTNAME}

MAINTAINER=	dev@freedomnas.io
COMMENT=	Pi-hole FTL, the DNS and DHCP engine with its API and web server
WWW=		https://github.com/pi-hole/FTL

LICENSE=	EUPL12

BUILD_DEPENDS=	xxd:sysutils/xxd
LIB_DEPENDS=	libgmp.so:math/gmp \
		libhogweed.so:security/nettle \
		libidn2.so:dns/libidn2 \
		libmbedtls.so:security/mbedtls4 \
		libunistring.so:devel/libunistring

USES=		cmake pkgconfig readline
USE_GITHUB=	yes
GH_ACCOUNT=	pi-hole
GH_PROJECT=	FTL

# Upstream's release with FreedomNAS's FreeBSD changes on top, one patch per
# change in files/ (bin/update-pihole.sh moves them to a new release)
FTL_HASH=	29c8b13f
FTL_DATE=	2026-10-17

# A tarball carries no git metadata, so the version comes from here; it is
# read while building (src/gen_version.cmake), not only when configuring
FTL_ENV=	GIT_BRANCH=master GIT_HASH=${FTL_HASH} \
		GIT_VERSION=v${DISTVERSION} GIT_TAG=v${DISTVERSION} \
		GIT_DATE=${FTL_DATE} STATIC=false
CONFIGURE_ENV=	${FTL_ENV}
MAKE_ENV=	${FTL_ENV}
CMAKE_ARGS=	-DCMAKE_DISABLE_FIND_PACKAGE_DBus=ON

PLIST_FILES=	bin/pihole-FTL

# The binary ends in a checksum of itself (pihole-FTL verify): stripping it
# would break that
do-install:
	${INSTALL} -m 555 ${BUILD_WRKSRC}/pihole-FTL ${STAGEDIR}${PREFIX}/bin/pihole-FTL

.include <bsd.port.mk>
