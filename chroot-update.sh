#! /bin/bash -x

# Use the current distro to pull main, but use upstream from stage/testing+$1/testing+$1/alpha
# (not everyone has upstream in his target distro)
# --Seb

SOURCES=/etc/apt/sources.list
DEBIAN_MIRROR=http://debian/debian
UBUNTU_MIRROR=http://ubuntu/ubuntu

if [ $# = 0 ] ; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -o DPkg::Options::=--force-confnew --yes --force-yes --fix-broken --purge debhelper aptitude
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -o DPkg::Options::=--force-confnew --yes --force-yes --fix-broken --purge
  exit 0
fi

addSource() {
  SRC="deb $1"
  grep -q "$SRC" ${SOURCES} || echo $SRC >> ${SOURCES}
}

REPOSITORY=$1
DISTRIBUTION=$2

case DISTRIBUTION in
  *-*) branch="`echo $DISTRIBUTION | perl -pe 's/.*?-/-/'`" ;;
  *) branch="" ;;
esac

# for our own build-deps
addSource "http://mephisto/public/$REPOSITORY $DISTRIBUTION main premium upstream"
case "$HOME" in # to sign packages with the real untangle java keystore
  *buildbot|seb*) addSource "http://mephisto/public/$REPOSITORY $DISTRIBUTION internal"
esac

# also search in nightly-$branch if not buildbot
case $DISTRIBUTION in
  nightly*) ;;
  *)
    case "$HOME" in
      *buildbot*) ;;
      *) addSource "http://mephisto/public/$REPOSITORY nightly${branch} main premium upstream"
    esac ;;
esac

if grep -q debian $SOURCES ; then
  grep -q "non-free" $SOURCES || perl -i -pe 's/main$/main contrib non-free/' $SOURCES
else
  grep -q "universe" $SOURCES || perl -i -pe 's/main$/main universe multiverse/' $SOURCES
fi

apt-get -q update

# do not ever prompt the user, even if the distribution name doesn't
# please dch
sed -i -e '/garbage/d' /usr/bin/dch

exit 0
