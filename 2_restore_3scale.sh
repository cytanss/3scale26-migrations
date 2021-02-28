#!/bin/bash
################################################################################
# 3scale 2.6 Operator Restore                                                   #
################################################################################

echo
echo "###############################################################################"
echo "#  MAKE SURE YOU ARE LOGGED IN:                                               #"
echo "#  $ oc login http://api.your.openshift.com                                   #"
echo "###############################################################################"

LOGGEDIN_USER=$(oc whoami)
CURRENT_PROJECT=$(oc project | cut -d'"' -f 2)
SERVER_API_URL=$(oc project | cut -d'"' -f 4)
WILDCARD_DNS=''

function restore() {
  
  echo "...debug WILDCARD_DNS === ${WILDCARD_DNS}"

  cd backupFiles

  oc apply -f system-seed.json
  oc apply -f system-database.json
  oc apply -f backend-internal-api.json
  oc apply -f system-events-hook.json
  oc apply -f system-app.json
  oc apply -f system-recaptcha.json
  oc apply -f system-redis.json
  oc apply -f zync.json
  oc apply -f system-master-apicast.json
  echo "Done with restoring up secrets"
  echo

  sed  's/"THREESCALE_SUPERDOMAIN.*/"THREESCALE_SUPERDOMAIN": "'${WILDCARD_DNS}'"/' ./system-environment.json > system-environment-new.json

  oc apply -f smtp.json
  oc apply -f system-environment-new.json
  oc apply -f apicast-environment.json
  echo "Done with restoring up configmap"
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
#read -p "Press Enter your OpenShift cluster apps wildcard DNS? " WILDCARD_DNS

# to be removed
WILDCARD_DNS='apps.cluster-9770.9770.sandbox230.opentlc.com'
# to be removed

echo "Wildcard DNS entered is ${WILDCARD_DNS}"
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
    echo "3scale 2.6 Restore Staring... ($(date))"
    
    restore

    END=`date +%s`
    echo "(Completed in $(( ($END - $START)/60 )) min $(( ($END - $START)%60 )) sec...)"
    echo 
  fi
fi