#!/bin/bash

usage() {
  echo "$0 -r <repository> -d <distribution> -b <builddir> [-u] [-e]"
  exit 1
}

debug() {
  echo "pass: " $HADES_KEY_PASS "alias: " $HADES_KEY_ALIAS
}

### CLI args
while getopts r:b:d:ueh option ; do
  case "$option" in
    r) TARGET_REP="$OPTARG" ;;
    b) BUILD_DIR="$OPTARG" ;;
    d) DISTRIBUTION="$OPTARG" ;;
    u) RELEASE="release" ;;
    e) CHECK_EXISTENCE="check-existence" ;;
    h) usage ;;
    \?) usage ;;
  esac
done

processResult() {
  result=$1
  [ $result = 0 ] && resultString="SUCCESS" || resultString="ERROR"
  echo "**** ${resultString}: make in $directory exited with return code $result"
  echo
  echo "# ======================="
  let results=results+result
  popd
}

### a few variables
FILE_IN="build-order.txt"
PKGTOOLS_HOME=`dirname $(readlink -f $0)`
results=0
export HADES_KEY_ALIAS HADES_KEY_PASS
debug

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
      case $repositories in
	*${REPOSITORY}*) build_dirs[${#build_dirs[*]}]="$package" ;;
	*) continue ;; # don't build this one for this repository
      esac ;;
  esac
done < $FILE_IN

# now cd into each dir in build_dirs and make
for directory in "${build_dirs[@]}" ; do
  echo 
  echo "# $directory"
  # cd into it, and attempt to build
  pushd "$directory"
  debug
  make -f $PKGTOOLS_HOME/Makefile DISTRIBUTION=$DISTRIBUTION REPOSITORY=$TARGET_REP version ${CHECK_EXISTENCE}
  result=$?      
  [ $result = 2 ] && processResult 0 && continue
  make -f $PKGTOOLS_HOME/Makefile DISTRIBUTION=$DISTRIBUTION REPOSITORY=$TARGET_REP source pkg-chroot ${RELEASE}
  result=$?
  processResult $result
done

exit $results
