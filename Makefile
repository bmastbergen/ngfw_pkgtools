DISTRIBUTION ?= $(USER)
PACKAGE_SERVER = mephisto
BUILDTOOLS_DIR = $(shell dirname $(MAKEFILE_LIST))
CHROOT_DIR = /var/cache/pbuilder
CHROOT_UPDATE_SCRIPT = $(BUILDTOOLS_DIR)/chroot-update.sh

checkroot:
	@if [ "$$UID" = "0" ]; then \
	  echo "You can't be root to build packages"; \
	  exit 1; \
	fi

clean: checkroot
	svn revert debian/changelog
	fakeroot debian/rules clean
	rm -f debian/version

version: checkroot
	svn revert debian/changelog
	sh $(BUILDTOOLS_DIR)/incVersion.sh $(DISTRIBUTION) VERSION=$(VERSION) REPOSITORY=$(REPOSITORY)

source: checkroot
	# so we can use that later to find out what to upload if needs be
	dpkg-parsechangelog | awk '/Version: / { print $$2 }' >| debian/version
	tar cz --exclude="*stamp*" \
		--exclude=".svn" \
		--exclude="debian" \
		--exclude="todo" \
		--exclude="staging" \
		-f ../`dpkg-parsechangelog | awk '/Source: / { print $$2 }'`_`perl -npe 's/(.+)-.*/$$1/ ; s/^.+://' debian/version`.orig.tar.gz ../`basename $$(pwd)`

# FIXME: duplicate code between pkg and pkg-pbuilder
pkg: checkroot
	# so we can use that later to find out what to upload if needs be
	dpkg-parsechangelog | awk '/Version: / { print $$2 }' >| debian/version
	# FIXME: sign packages when we move to apt 0.6
	# FIXME: don't clean before building !!!
	/usr/bin/debuild -e HADES_KEYSTORE -e HADES_KEY_ALIAS -e HADES_KEY_PASS -i -us -uc -sa
	svn revert debian/changelog

pkg-chroot: checkroot
	# so we can use that later to find out what to upload if needs be
	dpkg-parsechangelog | awk '/Version: / { print $$2 }' >| debian/version
	# FIXME: sign packages when we move to apt 0.6
	# FIXME: don't clean before building !!!
	CHROOT_ORIG=$(CHROOT_DIR)/$(REPOSITORY)+untangle.cow ; \
	CHROOT_WORK=$(CHROOT_DIR)/$(REPOSITORY)+untangle_`date -Iseconds`.cow ; \
	cp -al $${CHROOT_ORIG} $${CHROOT_WORK} ; \
	cowbuilder --execute --basepath $${CHROOT_WORK} --save-after-exec -- $(CHROOT_UPDATE_SCRIPT) $(REPOSITORY) $(DISTRIBUTION) ; \
	pdebuild --pbuilder cowbuilder --use-pdebuild-internal --debbuildopts "-i -us -uc -sa -e HADES_KEYSTORE -e HADES_KEY_ALIAS -e HADES_KEY_PASS" -- --basepath $${CHROOT_WORK} ; \
	rm -fr $${CHROOT_WORK}
	svn revert debian/changelog

release: checkroot
	dput -c $(BUILDTOOLS_DIR)/dput.cf $(PACKAGE_SERVER) ../`dpkg-parsechangelog | awk '/Source: / { print $$2 }'`_`perl -npe 's/^.+://' debian/version`*.changes

.PHONY: checkroot clean version source pkg release
