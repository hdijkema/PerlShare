
ifeq (${USER},root)
  SUDO=
else
  SUDO=sudo
endif

DESTDIR=/usr



all: 
	@echo "Usage:"
	@echo ""
	@echo "make ppa: upload to launchpad"
	@echo "make install: install locally, not by apt-get"
	@echo "make win32: win32 installer"
	@echo ""
	@echo "sudo = ${SUDO}, USER=${USER}"

ppa:
	@echo "to be done"

install:
	${SUDO} mkdir -p ${DESTDIR}/usr/share/perlshare
	${SUDO} cp *.pm *.pl ${DESTDIR}/usr/share/perlshare
	${SUDO} mkdir -p ${DESTDIR}/usr/share/perlshare/PerlShareCommon
	${SUDO} cp PerlShareCommon/* ${DESTDIR}/usr/share/perlshare/PerlShareCommon
	${SUDO} mkdir -p ${DESTDIR}/usr/share/perlshare/images
	${SUDO} cp images/* ${DESTDIR}/usr/share/perlshare/images
	${SUDO} chown -R root:root ${DESTDIR}/usr/share/perlshare
	${SUDO} chmod 755 ${DESTDIR}/usr/share/perlshare/PerlShare.pl
	${SUDO} mkdir -p ${DESTDIR}/usr/bin
	${SUDO} chmod 755 ${DESTDIR}/usr/bin
	${SUDO} cp perlshare ${DESTDIR}/usr/bin/perlshare
	${SUDO} chmod 755 ${DESTDIR}/usr/bin/perlshare
	${SUDO} (tar cf - share | (cd ${DESTDIR}/usr;tar --owner=root --group=root -x -f -))
		
