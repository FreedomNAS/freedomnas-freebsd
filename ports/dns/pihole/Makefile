PORTNAME=	pihole
DISTVERSION=	6.5
PORTREVISION=	4
CATEGORIES=	dns www
DIST_SUBDIR=	${PORTNAME}

MAINTAINER=	dev@freedomnas.io
COMMENT=	Network-wide ad blocking DNS server with a web interface
WWW=		https://pi-hole.net/

LICENSE=	EUPL12

RUN_DEPENDS=	bash:shells/bash \
		curl:ftp/curl \
		dig:dns/bind-tools \
		jq:textproc/jq \
		pihole-FTL:dns/pihole-ftl

USE_GITHUB=	nodefault
GH_TUPLE=	pi-hole:pi-hole:v${DISTVERSION}:core \
		pi-hole:web:v${WEB_VERSION}:web

NO_ARCH=	yes
NO_BUILD=	yes

SUB_FILES=	pkg-install pkg-message

# Upstream's release with FreedomNAS's FreeBSD changes on top, one patch per
# change in files/ (bin/update-pihole.sh moves them to a new release)
CORE_HASH=	f503a65d
WEB_VERSION=	6.6.1

WRKSRC=		${WRKDIR}/pi-hole-${DISTVERSION}
WEB_WRKSRC=	${WRKDIR}/web-${WEB_VERSION}

SCRIPTS=	advanced/Scripts/*.sh advanced/Scripts/database_migration/*.sh \
		advanced/Templates/pihole-FTL-prestart.sh \
		advanced/Templates/pihole-FTL-poststop.sh \
		advanced/Templates/pihole-FTL.rcd advanced/Templates/pihole.cron \
		advanced/Templates/*.sql gravity.sh pihole

# Pi-hole's Linux layout, moved to hier(7)
post-patch:
	cd ${WRKSRC} && ${REINPLACE_CMD} \
		-e 's|/etc/\.pihole|${PREFIX}/share/pihole|g' \
		-e 's|/opt/pihole|${PREFIX}/libexec/pihole|g' \
		-e 's|/etc/pihole|${PREFIX}/etc/pihole|g' \
		-e 's|/var/www/html|${PREFIX}/www/pihole|g' \
		-e 's|/etc/dnsmasq\.d|${PREFIX}/etc/dnsmasq.d|g' \
		${SCRIPTS}
	${REINPLACE_CMD} -e '/logrotate/d' ${WRKSRC}/advanced/Templates/pihole.cron
	${FIND} ${WRKSRC} -name '*.bak' -delete

do-install:
	${INSTALL_SCRIPT} ${WRKSRC}/pihole ${STAGEDIR}${PREFIX}/bin/pihole
	${MKDIR} ${STAGEDIR}${PREFIX}/libexec/pihole
	${INSTALL_SCRIPT} ${WRKSRC}/gravity.sh ${WRKSRC}/advanced/Scripts/*.sh \
		${WRKSRC}/advanced/Templates/pihole-FTL-prestart.sh \
		${WRKSRC}/advanced/Templates/pihole-FTL-poststop.sh \
		${STAGEDIR}${PREFIX}/libexec/pihole/
	${INSTALL_DATA} ${WRKSRC}/advanced/Scripts/COL_TABLE ${STAGEDIR}${PREFIX}/libexec/pihole/
	${ECHO_CMD} pkg > ${STAGEDIR}${PREFIX}/libexec/pihole/packaged
	${MKDIR} ${STAGEDIR}${DATADIR}/advanced/Scripts ${STAGEDIR}${DATADIR}/advanced/Templates
	${INSTALL_DATA} ${WRKSRC}/advanced/Templates/gravity.db.sql \
		${WRKSRC}/advanced/Templates/gravity_copy.sql ${STAGEDIR}${DATADIR}/advanced/Templates/
	cd ${WRKSRC}/advanced/Scripts && ${COPYTREE_SHARE} database_migration \
		${STAGEDIR}${DATADIR}/advanced/Scripts
	${PRINTF} 'VERSION=v${DISTVERSION}\nBRANCH=master\nHASH=${CORE_HASH}\n' \
		> ${STAGEDIR}${DATADIR}/.pkgversion
	${MKDIR} ${STAGEDIR}${WWWDIR}/admin
	cd ${WEB_WRKSRC} && ${COPYTREE_SHARE} "img scripts style vendor" ${STAGEDIR}${WWWDIR}/admin
	${INSTALL_DATA} ${WEB_WRKSRC}/*.lp ${WEB_WRKSRC}/LICENSE ${STAGEDIR}${WWWDIR}/admin/
	${PRINTF} 'VERSION=v${WEB_VERSION}\nBRANCH=master\nHASH=v${WEB_VERSION}\n' \
		> ${STAGEDIR}${WWWDIR}/admin/.pkgversion
	${INSTALL_SCRIPT} ${WRKSRC}/advanced/Templates/pihole-FTL.rcd \
		${STAGEDIR}${PREFIX}/etc/rc.d/pihole_ftl
	${MKDIR} ${STAGEDIR}${PREFIX}/etc/cron.d ${STAGEDIR}${PREFIX}/etc/newsyslog.conf.d
	${INSTALL_DATA} ${WRKSRC}/advanced/Templates/pihole.cron \
		${STAGEDIR}${PREFIX}/etc/cron.d/pihole
	${INSTALL_DATA} ${WRKSRC}/advanced/Templates/pihole.newsyslog \
		${STAGEDIR}${PREFIX}/etc/newsyslog.conf.d/pihole.conf
	${MKDIR} ${STAGEDIR}${PREFIX}/etc/pihole ${STAGEDIR}/var/log/pihole

.include <bsd.port.mk>
