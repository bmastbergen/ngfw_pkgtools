#! /bin/bash

usage() {
  echo "Usage: $0 -r <repository> -d <distribution> [-t <scheduledHour>]"
  exit 1
}

while getopts "r:d:t:" opt ; do
  case "$opt" in
    r) REPOSITORY=$OPTARG ;;
    d) DISTRIBUTION=$OPTARG ;;
    t) SCHEDULED_HOUR=$OPTARG ;;
    h) usage ;;
    \?) usage ;;
  esac
done
shift $(($OPTIND - 1))

[ ! $# = 0 ] && usage

pkgtools=`dirname $0`

. $pkgtools/release-constants.sh

SNAPSHOT=`date -d "-1day" "+%Y-%m-%d"`

if [ -z "$SCHEDULED_HOUR" ] || [ "$SCHEDULED_HOUR" -eq `date "+%H"` ] ; then
  repreproLocal gensnapshot $DISTRIBUTION $SNAPSHOT
fi
