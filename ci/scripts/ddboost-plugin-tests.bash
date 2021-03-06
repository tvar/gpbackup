#!/bin/bash

set -ex

# setup cluster and install gpbackup tools using gppkg
ccp_src/scripts/setup_ssh_to_cluster.sh
out=$(ssh -t mdw 'source env.sh && psql postgres -c "select version();"')
GPDB_VERSION=$(echo ${out} | sed -n 's/.*Greenplum Database \([0-9]\).*/\1/p')

# To prevent ddboost flaking with multiple pipelines due to backups running
# with the same timestamps, the current time in nanoseconds lowers the gpbackup
# timestamp collision rate. Nanoseconds for `date` command does not work on
# macOS.
TIME_NANO=$(date +%s%N)

mkdir -p /tmp/untarred
tar -xzf gppkgs/gpbackup-gppkgs.tar.gz -C /tmp/untarred
scp /tmp/untarred/gpbackup_tools*gp${GPDB_VERSION}*${OS}*.gppkg mdw:/home/gpadmin
ssh -t mdw "source env.sh; gppkg -i gpbackup_tools*.gppkg"

cat <<SCRIPT > /tmp/run_tests.bash
#!/bin/bash

set -ex
source env.sh

pushd gpbackup_ddboost_plugin
make test

# important: whitespace of yaml below is critical, do not change it
cat << CONFIG > \${HOME}/ddboost_config_replication.yaml
executablepath: \${GPHOME}/bin/gpbackup_ddboost_plugin
options:
  hostname: ${DD_SOURCE_HOST}
  username: ${DD_USER}
  storage_unit: GPDB
  directory: gpbackup_tests${GPDB_VERSION}
  replication: on
  pgport: 5432
  remote_hostname: ${DD_DEST_HOST}
  remote_username: ${DD_USER}
  remote_storage_unit: GPDB
  remote_directory: gpbackup_tests${GPDB_VERSION}
  password: ${DD_ENCRYPTED_PW}
  password_encryption: "on"
  remote_password: ${DD_ENCRYPTED_PW}
  remote_password_encryption: "on"
  gpbackup_ddboost_plugin: 66706c6c6e677a6965796f68343365303133336f6c73366b316868326764
CONFIG

# important: whitespace of yaml below is critical, do not change it
cat << CONFIG > \${HOME}/ddboost_config_replication_restore.yaml
executablepath: \${GPHOME}/bin/gpbackup_ddboost_plugin
options:
  hostname: ${DD_DEST_HOST}
  username: ${DD_USER}
  password: ${DD_PW}
  storage_unit: GPDB
  directory: gpbackup_tests${GPDB_VERSION}
  pgport: 5432
CONFIG

pushd \${GOPATH}/src/github.com/greenplum-db/gpbackup/plugins

./plugin_test_bench.sh \${GPHOME}/bin/gpbackup_ddboost_plugin \${HOME}/ddboost_config_replication.yaml \${HOME}/ddboost_config_replication_restore.yaml

# exercise boostfs, which is mounted at /data/gpdata/dd_dir
pushd \${GOPATH}/src/github.com/greenplum-db/gpbackup

# NOTE: This is a temporary hotfix intended to skip these tests when running on CCP cluster
#       because the backup artifact that these tests are using only works on local clusters.
sed -i 's|\tIt\(.*\)\(--on-error-continue\)|\tPIt\1\2|' end_to_end/end_to_end_suite_test.go

make end_to_end CUSTOM_BACKUP_DIR=/data/gpdata/dd_dir/end_to_end_GPDB${GPDB_VERSION}/${TIME_NANO}
SCRIPT

chmod +x /tmp/run_tests.bash
scp /tmp/run_tests.bash mdw:/home/gpadmin/run_tests.bash
ssh -t mdw "/home/gpadmin/run_tests.bash"
