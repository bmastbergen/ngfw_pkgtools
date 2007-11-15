#! /bin/bash

# Use the current distro to pull main, but use upstream from testing
# (not everyone has upstream in his target distro)
# --Seb

SOURCES=/etc/apt/sources.list

echo deb http://mephisto/public/$1 $2 main >> ${SOURCES}
echo deb http://mephisto/public/$1 testing upstream >> ${SOURCES}
apt-get update
