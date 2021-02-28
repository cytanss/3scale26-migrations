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

function backup() {
  
  rm -rf backupFiles
  mkdir backupFiles
  cd backupFiles

  oc rsh $(oc get pods -l 'deploymentConfig=system-mysql' -o json | jq -r '.items[0].metadata.name') bash -c 'export MYSQL_PWD=${MYSQL_ROOT_PASSWORD}; mysqldump --single-transaction -hsystem-mysql -uroot system' | gzip > system-mysql-backup.gz
  echo "Done with backing up system-mysql"
  echo

  mkdir local
  mkdir local/dir
  oc rsync $(oc get pods -l 'deploymentConfig=system-app' -o json | jq '.items[0].metadata.name' -r):/opt/system/public/system ./local/dir
  echo "Done with backing up system-storage"
  echo

  oc scale dc zync --replicas=0
  oc scale dc zync-que --replicas=0
  sleep 10
  oc rsh $(oc get pods -l 'deploymentConfig=zync-database' -o json | jq '.items[0].metadata.name' -r) bash -c 'pg_dumpall -c --if-exists' | gzip > zync-database-backup.gz
  sleep 3
  oc scale dc zync --replicas=1
  oc scale dc zync-que --replicas=1
  sleep 3
  echo "Done with backing up zync-database"
  echo

  oc cp $(oc get pods -l 'deploymentConfig=backend-redis' -o json | jq '.items[0].metadata.name' -r):/var/lib/redis/data/dump.rdb ./backend-redis-dump.rdb
  echo "Done with backing up backend-redis"
  echo

  oc cp $(oc get pods -l 'deploymentConfig=system-redis' -o json | jq '.items[0].metadata.name' -r):/var/lib/redis/data/dump.rdb ./system-redis-dump.rdb
  echo "Done with backing up system-redis"
  echo

  oc get secrets system-seed -o json --export > system-seed.json
  oc get secrets system-database -o json --export > system-database.json
  oc get secrets backend-internal-api -o json --export > backend-internal-api.json
  oc get secrets system-events-hook -o json --export > system-events-hook.json
  oc get secrets system-app -o json --export > system-app.json
  oc get secrets system-recaptcha -o json --export > system-recaptcha.json
  oc get secrets system-redis -o json --export > system-redis.json
  oc get secrets zync -o json --export > zync.json
  oc get secrets system-master-apicast -o json --export > system-master-apicast.json
  echo "Done with backing up secrets"
  echo
  
  oc get configmaps system-environment -o json --export > system-environment.json
  oc get configmaps apicast-environment -o json --export > apicast-environment.json
  oc get configmaps smtp -o json --export > smtp.json
  echo "Done with backing up configmaps"
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
    echo "3scale 2.6 BackUp Staring... ($(date))"
    
    backup

    END=`date +%s`
    echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec...)"
    echo 
  fi
fi