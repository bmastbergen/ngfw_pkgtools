#!/bin/sh

# usage...
if [ ! $# -eq 3 ] ; then 
  echo "Usage: $0 distribution VERSION=[version] REPOSITORY=[repository]" && exit 1
fi

rm -f debian/changelog.dch

# CL args
distribution=${1}
version=${2/VERSION=}
versionGiven=$version
repository=${3/REPOSITORY=}

if [ -z "$version" ] ; then
  # not exactly kosher, but I'll contend that incVersion.sh is only
  # called from the Makefile :>
  versionFile=`dirname $0`/../VERSION

  # get 2 values from SVN: last changed revision & timestamp for the
  # current directory
  revision=`svn info --recursive . | awk '/Last Changed Rev: / { print $4 }' | sort -n | tail -1`
  timestamp=`svn info --recursive . | awk '/Last Changed Date:/ { gsub(/-/, "", $4) ; print $4 }' | sort -n | tail -1`

  # this is how we figure out if we're up-to-date or not
  hasLocalChanges=`svn status | grep -v -E '^([X?]|Fetching external item into|Performing status on external item at|$)'`

  # this is the base version; it will be tweaked a bit oif need be:
  # - append a local modification marker is we're not up to date
  # - prepend the upstream version if UNTANGLE-KEEP-UPSTREAM-VERSION exists
  baseVersion=`cat $versionFile`~svn${timestamp}r${revision}

  if [ -f UNTANGLE-KEEP-UPSTREAM-VERSION ] ; then
    previousUpstreamVersion=`dpkg-parsechangelog | awk '/Version: / { gsub(/-.*/, "", $2) ; print $2 }'`
    baseVersion=${previousUpstreamVersion}+${baseVersion}
  fi

  if [ -z "$hasLocalChanges" ] ; then
    version=$baseVersion
  else
    echo "The changes were: $hasLocalChanges"
    version=${baseVersion}+$USER`date +"%Y%m%dT%H%M%S"`
    distribution=$USER
  fi
else # force version
  version=$version
fi

if [ -z "${repository}" ] ; then
  # figure out what platform we're on
  grep Debian /etc/issue && i=3 || i=2
  case `head -1 /etc/issue | awk "{ print \\$$i }"` in
    lenny/sid) repository=sid ;;
    4.0) repository=etch ;; 
    3.1) repository=sarge ;;
    7.04*) repository=feisty ;;
    7.10*) repository=gutsy ;;
    8.04*) repository=gutsy ;;
    *) echo "Couldn't guess your platform, giving up" ; exit 1 ;;
  esac
fi

version=${version}-1${repository}

echo "Setting version to \"${version}\", distribution to \"$distribution\""
DEBEMAIL="${DEBEMAIL:-${USER}@untangle.com}" dch -v ${version} -D ${distribution} "auto build"
# check changelog back in if version was forced
[ -n "$versionGiven" ] && svn commit debian/changelog -m "Forcing version to $version"
echo " done."
