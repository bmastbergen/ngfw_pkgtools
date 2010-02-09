#! /bin/bash

usage() {
  echo "Usage: $0 [-s] [-m] [-w] -r <repository> -d <distribution>"
  echo "-s : simulate"
  echo "-m : manifest"
  echo "-w : wipe out target before sync'ing"
  exit 1
}

while getopts "wshr:d:m" opt ; do
  case "$opt" in
    s) simulate=1 ;;
    m) MANIFEST=1 ;;
    w) WIPE_OUT_TARGET=1 ;;
    r) REPOSITORY=$OPTARG ;;
    d) DISTRIBUTION=$OPTARG ;;
    h) usage ;;
    \?) usage ;;
  esac
done
shift $(($OPTIND - 1))
if [ ! $# = 0 ] ; then
  usage
fi

[ -z "$REPOSITORY" -o -z "$DISTRIBUTION" ] && usage && exit 1

pkgtools=`dirname $0`
. $pkgtools/release-constants.sh

tmp_base=/tmp/sync-$REPOSITORY-$DISTRIBUTION-`date -Iminutes`
diffCommand="$pkgtools/apt-chroot-utils/compare-sources.py `hostname`,$REPOSITORY,$DISTRIBUTION user:metavize@updates.untangle.com,$REPOSITORY,$DISTRIBUTION $tmp_base"

# MAIN
copyRemotePkgtools

if [ -z "$simulate" ] ; then
#  $SSH_COMMAND /etc/init.d/untangle-gpg-agent start
  /bin/rm -f ${tmp_base}*
  [ -n "$MANIFEST" ] && python $diffCommand
  # in case the previous diff failed, we still want mutt to email out
  # the notice
  [ -f ${tmp_base}*.txt ] || touch ${tmp_base}.txt
  [ -f ${tmp_base}*.csv ] || touch ${tmp_base}.csv


  # wipe out target distribution first
  [ -n "$WIPE_OUT_TARGET" ] && remoteCommand ./remove-packages.sh -r ${REPOSITORY} -d ${DISTRIBUTION}

  date="`date`"
  repreproRemote --noskipold update ${DISTRIBUTION} || exit 1

  # also remove source packages for premium; this is really just a
  # safety measure now, as the update process itself is smarter and
  # knows not to pull sources for premium.
#  $SSH_COMMAND ./remove-packages.sh -r ${REPOSITORY} -d ${DISTRIBUTION} -t dsc -c premium

  repreproRemote export ${DISTRIBUTION} || exit 1

  if [ -n "$MANIFEST" ] ; then
    attachments="-a ${tmp_base}*.txt -a ${tmp_base}*.csv"

    mutt -F $MUTT_CONF_FILE $attachments -s "[Distro sync] $REPOSITORY: `hostname`/$DISTRIBUTION pushed to updates.u.c/$DISTRIBUTION" $RECIPIENT <<EOF
Effective `date` (started at $date).

Attached are the diff files for this push, generated by running
the following command prior to actually promoting:

  $diffCommand

--ReleaseMaster ($USER@`hostname`)

EOF
  fi

  /bin/rm -f ${tmp_base}*
#  $SSH_COMMAND /etc/init.d/untangle-gpg-agent stop
else
  repreproRemote "checkupdate $DISTRIBUTION 2>&1 | grep upgraded | sort -u"
  remoteCommand ./remove-packages.sh -r ${REPOSITORY} -d ${DISTRIBUTION} -T dsc -C premium -s
fi

# remove remote pkgtools
removeRemotePkgtools
