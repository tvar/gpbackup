#!/bin/bash
set -ex

# USAGE: ./gpbackup_rpm.sh [gpbackup version] [source targz file]
# Example: ./gpbackup_rpm.sh 1.8.0 mybinaries.tar.gz
if [ "$#" -ne 2 ]; then
    echo "./gpbackup_rpm.sh [gpbackup version] [source targz file]"
fi

GPBACKUP_VERSION=$1
SOURCE_TARGZ=$2

GPBACKUP_DIR=$(dirname $0)/../..

# Create rpm directory structure
RPMROOT=/tmp/gpbackup_rpm
rm -rf ${RPMROOT}
mkdir -p ${RPMROOT}/{BUILD,RPMS,SOURCES,SPECS,SRPMS}


# Interpolate version values to create spec file for rpm
rm -f temp.spec
( echo "cat <<EOF >${RPMROOT}/SPECS/gpbackup.spec";   cat ${GPBACKUP_DIR}/gppkg/gpbackup.spec.in;   echo "EOF"; ) >temp.spec
. temp.spec
rm -f temp.spec

# Move source targz to SOURCES
cp ${SOURCE_TARGZ} ${RPMROOT}/SOURCES/.

rpmbuild -bb ${RPMROOT}/SPECS/gpbackup.spec --define "%_topdir ${RPMROOT}" --define "debug_package %{nil}"

echo "Successfully built RPM"
