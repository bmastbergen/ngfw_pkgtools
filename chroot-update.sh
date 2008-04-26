#! /bin/bash

# Use the current distro to pull main, but use upstream from stage/testing+$1/testing+$1/alpha
# (not everyone has upstream in his target distro)
# --Seb

SOURCES=/etc/apt/sources.list

if [ $# = 0 ] ; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get --yes dist-upgrade
  exit 0
fi

REPOSITORY=$1
DISTRIBUTION=$2

case DISTRIBUTION in
  *-*) branch="`echo $DISTRIBUTION | perl -pe 's/.*?-/-/'`" ;;
  *) branch="" ;;
esac

# for our own build-deps
echo deb http://mephisto/public/$REPOSITORY $DISTRIBUTION main premium upstream >> ${SOURCES}
case "$HOME" in
  *buildbot|seb*) echo deb http://mephisto/public/$REPOSITORY $DISTRIBUTION internal >> ${SOURCES}
esac

# also search in nightly-$branch if not buildbot
case $DISTRIBUTION in
  nightly*) ;;
  *) if [ "$USER" != "buildbot" ]; then
              echo deb http://mephisto/public/$REPOSITORY nightly${branch} main premium upstream >> ${SOURCES}
     fi ;;
esac

apt-get -q update

exit 0
