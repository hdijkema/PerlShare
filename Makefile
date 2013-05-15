
all: 
	@echo "Usage:"
	@echo ""
	@echo "make ppa: upload to launchpad"
	@echo "make install: install locally, not by apt-get"
	@echo "make win32: win32 installer"
	@echo ""

ppa:
	@echo "to be done"

install:
	sudo mkdir -p /usr/share/perlshare
	sudo cp *.pm *.pl /usr/share/perlshare
	sudo mkdir -p /usr/share/perlshare/PerlShareCommon
	sudo cp PerlShareCommon/* /usr/share/perlshare/PerlShareCommon
	sudo mkdir -p /usr/share/perlshare/images
	sudo cp images/* /usr/share/perlshare/images
	sudo chown -R root:root /usr/share/perlshare
	sudo chmod 755 /usr/share/perlshare/PerlShare.pl
	sudo cp perlshare /usr/bin/perlshare
	sudo chmod 755 /usr/bin/perlshare
	


		
