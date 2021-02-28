#!/bin/bash
################################################################################
# 3scale 2.6 Template Backup                                                   #
################################################################################

echo
echo "###############################################################################"
echo "#  MAKE SURE YOU ARE LOGGED IN:                                               #"
echo "#  $ oc login http://console.your.openshift.com                               #"
echo "###############################################################################"

LOGGEDIN_USER=$(oc whoami)
CURRENT_PROJECT=$(oc project | cut -d'"' -f 2)
SERVER_API_URL=$(oc project | cut -d'"' -f 4)

function restore() {

  cd backupFiles

  oc cp ./system-mysql-backup.gz $(oc get pods -l 'deploymentConfig=system-mysql' -o json | jq '.items[0].metadata.name' -r):/var/lib/mysql
  oc rsh $(oc get pods -l 'deploymentConfig=system-mysql' -o json | jq -r '.items[0].metadata.name') bash -c 'gzip -d ${HOME}/system-mysql-backup.gz'
  oc rsh $(oc get pods -l 'deploymentConfig=system-mysql' -o json | jq -r '.items[0].metadata.name') bash -c 'export MYSQL_PWD=${MYSQL_ROOT_PASSWORD}; mysql -hsystem-mysql -uroot system < ${HOME}/system-mysql-backup'
  echo "Done with restoring system-mysql"
  echo

  oc rsync ./local/dir/system/ $(oc get pods -l 'deploymentConfig=system-app' -o json | jq '.items[0].metadata.name' -r):/opt/system/public/system
  echo "Done with restoring system-storage"
  echo
    
  ZYNC_REPLICAS=$(oc get dc/zync -o json | jq -r '.spec.replicas')
  #echo $ZYNC_REPLICAS
  ZYNC_QUE_REPLICAS=$(oc get dc/zync-que -o json | jq -r '.spec.replicas')
  #echo $ZYNC_QUE_REPLICAS
  oc scale dc zync --replicas=0
  oc scale dc zync-que --replicas=0
  sleep 12
  oc cp ./zync-database-backup.gz $(oc get pods -l 'deploymentConfig=zync-database' -o json | jq '.items[0].metadata.name' -r):/var/lib/pgsql/
  oc rsh $(oc get pods -l 'deploymentConfig=zync-database' -o json | jq -r '.items[0].metadata.name') bash -c 'gzip -d ${HOME}/zync-database-backup.gz'
  oc rsh $(oc get pods -l 'deploymentConfig=zync-database' -o json | jq -r '.items[0].metadata.name') bash -c 'psql -f ${HOME}/zync-database-backup'
  sleep 3
  oc scale dc zync --replicas=$ZYNC_REPLICAS
  oc scale dc zync-que --replicas=$ZYNC_QUE_REPLICAS
  sleep 3
  echo "Done with restoring zync-database"
  echo
  
  rm -f redis-config.yaml
  rm -f redis-config-new.yaml
  oc get cm redis-config -o yaml > redis-config.yaml
  sed -e 's/save .*/#&/' -e 's/appendonly yes/appendonly no/'  ./redis-config.yaml > redis-config-new.yaml
  oc replace -f redis-config-new.yaml --force
  oc rollout latest dc/backend-redis
  oc rollout status dc/backend-redis
  sleep 10
  oc rsh $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'mv ${HOME}/data/dump.rdb ${HOME}/data/dump.rdb-old'
  oc rsh $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'mv ${HOME}/data/appendonly.aof ${HOME}/data/appendonly.aof-old'
  oc cp ./backend-redis-dump.rdb $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r):/var/lib/redis/data/dump.rdb
  oc rollout latest dc/backend-redis
  oc rollout status dc/backend-redis
  sleep 15
  oc rsh $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'redis-cli BGREWRITEAOF'
  CONTINUE=1
  while [ $CONTINUE -gt 0 ] 
  do
    #echo "going to sleep for 3"
    sleep 3
    PROGRESS=$(oc rsh $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'redis-cli info' | grep aof_rewrite_in_progress | cut -d':' -f 2)
    if [[ $PROGRESS == "0"* ]];
    then
      CONTINUE=0
    else 
      CONTINUE=`expr 1 + $CONTINUE`
      echo $CONTINUE
    fi
  done
  oc replace -f redis-config.yaml --force
  oc rollout latest dc/backend-redis
  oc rollout status dc/backend-redis
  sleep 10
  echo "Done with restoring backend-redis"
  echo

  oc replace -f redis-config-new.yaml --force
  oc rollout latest dc/system-redis
  oc rollout status dc/system-redis
  sleep 10
  oc rsh $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'mv ${HOME}/data/dump.rdb ${HOME}/data/dump.rdb-old'
  oc rsh $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'mv ${HOME}/data/appendonly.aof ${HOME}/data/appendonly.aof-old'
  oc cp ./system-redis-dump.rdb $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r):/var/lib/redis/data/dump.rdb
  oc rollout latest dc/system-redis
  oc rollout status dc/system-redis
  sleep 10
  oc rsh $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'redis-cli BGREWRITEAOF'
  CONTINUE=1
  while [ $CONTINUE -gt 0 ] 
  do
    #echo "going to sleep for 3"
    sleep 3
    PROGRESS=$(oc rsh $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r) bash -c 'redis-cli info' | grep aof_rewrite_in_progress | cut -d':' -f 2)
    if [[ $PROGRESS == "0"* ]];
    then
      CONTINUE=0
    else 
      CONTINUE=`expr 1 + $CONTINUE`
      echo $CONTINUE
    fi
  done
  oc replace -f redis-config.yaml --force
  oc rollout latest dc/system-redis
  oc rollout status dc/system-redis
  sleep 10
  echo "Done with restoring system-redis"
  echo

  oc rollout latest dc/backend-worker
  oc rollout status dc/backend-worker
  sleep 10
  echo "Done with restoring backend-worker"
  echo

  oc rollout latest dc/system-app
  oc rollout status dc/system-app
  sleep 10
  echo "Done with restoring system-app"
  echo
  
  return
}

#echo "function echo_header"
function echo_header() {
  echo
  echo "########################################################################"
  echo $1
  echo "########################################################################"
}

################################################################################
# MAIN:                                                                        #
################################################################################

echo_header "3scale 2.6 Temaplate to Operator Migration Demo"
echo User Logged in = ${LOGGEDIN_USER}
echo Current Porject = ${CURRENT_PROJECT}
echo OpenShift API URL = ${SERVER_API_URL}

echo
read -p "Press Enter Y to confirm to proceed? " CONFIRMED
if [ -z "$CONFIRMED" ];
then
  echo "Process canceled!"
  exit 255
else
  if [ $CONFIRMED != "Y" ] && [ $CONFIRMED != "y" ];
  then 
    echo "Process canceled!"
    exit 255
  else
    START=`date +%s`
    echo
    echo "3scale 2.6 Restore 2 Staring... ($(date))"
    
    restore

    END=`date +%s`
    echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec...)"
    echo 
  fi
fi