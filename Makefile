# default shell
SHELL := /bin/bash
shell := /bin/bash

# pwd of this Makefile
PKGTOOLS_DIR := $(shell dirname $(MAKEFILE_LIST))

# overridables
DISTRIBUTION ?= $(USER)
PACKAGE_SERVER ?= mephisto
REPOSITORY ?= $(shell $(PKGTOOLS_DIR)/getPlatform.sh)
TIMESTAMP ?= $(shell date "+%Y-%m-%dT%H%M%S_%N")

# binary upload
ifneq ($(origin RECURSIVE), undefined)
  REC := -a
endif

# debuild/dpkg-buildpackage options
DEBUILD_OPTIONS := -e HADES_KEYSTORE -e HADES_KEY_ALIAS -e HADES_KEY_PASS
DPKGBUILDPACKAGE_OPTIONS := -i -us -uc
ifeq ($(origin BINARY_UPLOAD), undefined)
  DPKGBUILDPACKAGE_OPTIONS += -sa
else
  DPKGBUILDPACKAGE_OPTIONS += -B
endif

# cwd
CUR_DIR := $(shell basename `pwd`)

# destination dir for the debian files (dsc, changes, etc)
DEST_DIR := $(shell echo /tmp/$(REPOSITORY)-$${PPID})

# current package to build
SOURCE_NAME := $(shell dpkg-parsechangelog 2> /dev/null | awk '/^Source:/{print $$2}')
VERSION_FILE := debian/version
DESTDIR_FILE := debian/destdir

# chroot stuff
CHROOT_DIR := /var/cache/pbuilder
CHROOT_UPDATE_SCRIPT := $(PKGTOOLS_DIR)/chroot-update.sh
CHROOT_UPDATE_EXISTENCE_SCRIPT := $(PKGTOOLS_DIR)/chroot-update-existence.sh
CHROOT_CHECK_PACKAGE_VERSION_SCRIPT := $(PKGTOOLS_DIR)/chroot-check-for-package-version.sh
ARCH := $(shell uname -m | grep -q 64 && echo _amd64)
CHROOT_BASE := $(CHROOT_DIR)/$(REPOSITORY)+untangle$(ARCH)
CHROOT_ORIG := $(CHROOT_BASE).cow
CHROOT_WORK := $(CHROOT_BASE)_$(TIMESTAMP).cow
CHROOT_EXISTENCE := $(CHROOT_BASE)_$(TIMESTAMP)_existence.cow

# used for checking existence of a package on the package server
AVAILABILITY_MARKER := __NOT-AVAILABLE__

########################################################################
# Rules
.PHONY: checkroot create-dest-dir revert-changelog parse-changelog move-debian-files clean-debian-files clean-chroot-files clean-build clean version-real version check-existence source pkg-real pkg pkg-chroot-real pkg-chroot release release-deb create-existence-chroot remove-existence-chroot remove-chroot create-chroot upgrade-base-chroot

checkroot:
	@if [ "$$UID" = "0" ] ; then \
	  echo "You can't be root to build packages"; \
	fi

create-dest-dir:
	mkdir -p $(DEST_DIR)
	rm -fr $(DEST_DIR)/*
	echo $(DEST_DIR) >| $(DESTDIR_FILE)

revert-changelog: # do not leave it locally modified
	svn revert debian/changelog

parse-changelog: # store version so we can use that later for uploading
	dpkg-parsechangelog | awk '/Version:/{print $$2}' >| $(VERSION_FILE)

move-debian-files:
	find .. -maxdepth 1 -name "*`perl -pe 's/^.+://' $(VERSION_FILE)`*" -regex '.*\.\(upload\|changes\|udeb\|deb\|upload\|dsc\|build\|diff\.gz\)' -exec mv "{}" `cat $(DESTDIR_FILE)` \;
	find .. -maxdepth 1 -name "*`perl -pe 's/^.+:// ; s/-.*//' $(VERSION_FILE)`*orig.tar.gz" -exec mv "{}" `cat $(DESTDIR_FILE)` \;

clean-build: checkroot
	fakeroot debian/rules clean
clean-untangle-files: revert-changelog
	rm -fr `cat $(DESTDIR_FILE)`
	rm -f $(VERSION_FILE) $(DESTDIR_FILE)
clean-debian-files:
	if [ -f $(DESTDIR_FILE) ] && [ -d `cat $(DESTDIR_FILE)` ] ; then \
	  find `cat $(DESTDIR_FILE)` -maxdepth 1 -name "*`perl -pe 's/^.+://' $(VERSION_FILE)`*" -regex '.*\.\(changes\|deb\|upload\|dsc\|build\|diff\.gz\)' -exec rm -f "{}" \; ; \
 	  find `cat $(DESTDIR_FILE)` -maxdepth 1 -name "*`perl -pe 's/^.+:// ; s/-.*//' $(VERSION_FILE)`*orig.tar.gz" -exec rm -f "{}" \; ; \
	fi
clean-chroot-files: clean-debian-files clean-untangle-files

clean: clean-chroot-files clean-build remove-chroot remove-existence-chroot

version-real: checkroot
	bash $(PKGTOOLS_DIR)/incVersion.sh $(DISTRIBUTION) VERSION=$(VERSION) REPOSITORY=$(REPOSITORY)
version: version-real parse-changelog

create-existence-chroot:
	if [ ! -d $(CHROOT_EXISTENCE) ] ; then \
          sudo cp -al $(CHROOT_ORIG) $(CHROOT_EXISTENCE) ; \
          sudo cowbuilder --execute --save-after-exec --basepath $(CHROOT_EXISTENCE) -- $(CHROOT_UPDATE_EXISTENCE_SCRIPT) $(REPOSITORY) $(DISTRIBUTION) ; \
          sudo cp -f $(CHROOT_CHECK_PACKAGE_VERSION_SCRIPT) $(CHROOT_EXISTENCE) ; \
        fi
remove-existence-chroot:
	sudo rm -fr $(CHROOT_EXISTENCE)
check-existence: create-existence-chroot
	if [ -z "$(ARCH)" ] ; then \
	  dh_switch="" ; \
	else \
	  dh_switch="-a" ; \
	fi ; \
	packageName=`dh_listpackages $${dh_switch} | head -1` ;\
	output=`sudo chroot $(CHROOT_EXISTENCE) /$(shell basename $(CHROOT_CHECK_PACKAGE_VERSION_SCRIPT)) "$${packageName}" $(shell cat $(VERSION_FILE)) $(AVAILABILITY_MARKER)` ; \
	echo "$${output}" | grep -q $(AVAILABILITY_MARKER) && echo "Version $(shell cat $(VERSION_FILE)) of $(SOURCE_NAME) is not available in $(REPOSITORY)/$(DISTRIBUTION)"

source: checkroot parse-changelog
	tar cz --exclude="*stamp*" --exclude=".svn" --exclude="debian" \
	       --exclude="todo" --exclude="staging" \
	       -f ../$(SOURCE_NAME)_`dpkg-parsechangelog | awk '/^Version:/{gsub(/(^.+:|-.*)/, "", $$2) ; print $$2}'`.orig.tar.gz ../$(CUR_DIR)

pkg-real: checkroot parse-changelog
	/usr/bin/debuild $(DEBUILD_OPTIONS) $(DPKGBUILDPACKAGE_OPTIONS)
pkg: create-dest-dir pkg-real move-debian-files

upgrade-base-chroot:
	sudo cowbuilder --execute --basepath $(CHROOT_ORIG) --save-after-exec -- $(CHROOT_UPDATE_SCRIPT)

create-chroot:
	if [ ! -d $(CHROOT_WORK) ] ; then \
          sudo rm -fr $(CHROOT_WORK) ; \
          sudo cp -al $(CHROOT_ORIG) $(CHROOT_WORK) ; \
          sudo cowbuilder --execute --save-after-exec --basepath $(CHROOT_WORK) -- $(CHROOT_UPDATE_SCRIPT) $(REPOSITORY) $(DISTRIBUTION) ; \
        fi
remove-chroot:
	sudo rm -fr $(CHROOT_WORK)
pkg-chroot-real: checkroot parse-changelog create-dest-dir
	# if we depend on an untangle-* package, we want to apt-get update
	# to get the latest available version (that might have been uploaded
	# during the current make-build.sh run)
	if grep -E '^Build-Depends:.*untangle' debian/control ; then \
          sudo cowbuilder --execute --save-after-exec --basepath $(CHROOT_WORK) -- $(CHROOT_UPDATE_SCRIPT) $(REPOSITORY) $(DISTRIBUTION) ; \
        fi
	pdebuild --pbuilder cowbuilder --use-pdebuild-internal \
		 --buildresult `cat $(DESTDIR_FILE)` \
	         --debbuildopts "$(DPKGBUILDPACKAGE_OPTIONS)" -- \
	         --basepath $(CHROOT_WORK)
pkg-chroot: create-dest-dir create-chroot pkg-chroot-real move-debian-files

release:
	dput -c $(PKGTOOLS_DIR)/dput.cf $(PACKAGE_SERVER)_$(REPOSITORY) `cat $(DESTDIR_FILE)`/$(SOURCE_NAME)_`perl -pe 's/^.+://' $(VERSION_FILE)`*.changes

release-deb:
	$(PKGTOOLS_DIR)/release-binary-packages.sh -r $(REPOSITORY) -d $(DISTRIBUTION) $(REC)
