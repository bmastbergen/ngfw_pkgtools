#!/bin/bash

CHROOT_BASE=

usage() {
  echo "$0 -r <repository> -d <distribution> -b <builddir> [-n] [-a <arch>] [-v <version>] [-u] [-e] [-c]"
  exit 1
}

### CLI args
while getopts r:b:d:v:a:uench option ; do
  case "$option" in
    r) TARGET_REP="$OPTARG" ;;
    b) BUILD_DIR="$OPTARG" ;;
    d) DISTRIBUTION="$OPTARG" ;;
    v) VERSION="$OPTARG" ;;
    n) BINARY_UPLOAD="BINARY_UPLOAD=true" ;;
    c) CHECKROOT_UPGRADE="true" ;;
    u) RELEASE="release" ;;
    a) ARCH="$OPTARG" ;;
    e) CHECK_EXISTENCE="check-existence" ;;
    h) usage ;;
    \?) usage ;;
  esac
done
[ -z "$ARCH" ] && ARCH=i386
MAKE_VARIABLES="DISTRIBUTION=${DISTRIBUTION} REPOSITORY=${TARGET_REP} ${BINARY_UPLOAD} TIMESTAMP=`date +%Y-%m-%dT%H%M%S_%N`"
if [ -n "$VERSION" ] ; then
  MAKE_VARIABLES="$MAKE_VARIABLES VERSION=\"${VERSION}\""
  VERSION_TARGET=""
else
  VERSION_TARGET="version"
fi

processResult() {
  result=$1
  [ $result = 0 ] && resultString="SUCCESS" || resultString="ERROR"
  let results=results+result
  make -f $PKGTOOLS_HOME/Makefile $MAKE_VARIABLES clean-chroot-files
  echo "**** ${resultString}: make in $directory exited with return code $result"
  echo
  echo "# ======================="
  popd > /dev/null
}

### a few variables
FILE_IN="build-order.txt"
PKGTOOLS_HOME=`dirname $(readlink -f $0)`
results=0

### main
# cd into the main trunk (the buildbot is already in there)
cd "${BUILD_DIR}" 2> /dev/null

# first grab the content of the build-order.txt file
build_dirs=()
while read package repositories ; do
  case $package in
    \#*) continue ;; # comment
    "") continue ;; # empty line
    *) # yes
      if [[ "$repositories" = *${TARGET_REP}* ]] ; then
	if [ $ARCH = "i386" ] || grep -qE "^Architecture:.*(any|$ARCH)" $package/debian/control ; then
	  build_dirs[${#build_dirs[*]}]="$package"
	fi
      fi ;;
  esac
done < $FILE_IN

# do this only once, instead of for each package
[ -n "$CHECKROOT_UPGRADE" ] && make -f $PKGTOOLS_HOME/Makefile $MAKE_VARIABLES upgrade-base-chroot

# now cd into each dir in build_dirs and make
for directory in "${build_dirs[@]}" ; do
  echo 
  echo "# $directory"
  # cd into it, and attempt to build
  pushd "$directory" > /dev/null
  make -f $PKGTOOLS_HOME/Makefile $MAKE_VARIABLES clean-chroot-files $VERSION_TARGET $CHECK_EXISTENCE
  result=$?      
  [ $result = 2 ] && processResult 0 && continue
  make -f $PKGTOOLS_HOME/Makefile $MAKE_VARIABLES source pkg-chroot ${RELEASE}
  result=$?
  processResult $result
  # if we're building only arch-dependent pkgs, we need to give the IQD time to process uploads
  [ $ARCH = "i386" ] || sleep 31
done

# do this last
make -f $PKGTOOLS_HOME/Makefile $MAKE_VARIABLES remove-existence-chroot remove-chroot

exit $results
