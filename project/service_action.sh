#!/bin/bash

LOG_PATH="/tmp"
LOG_NAME="service-action.log"
ANSIBLE_LASTLOG="last-playbook-run.log"
ANSIBLE_PATH="/var/lib/postgresql/playbook"
LOG_PREFIX=`date +%y/%m/%d_%H:%M:%S.%N`

if [[ "$#" -ne 3 ]]; then
    echo $LOG_PREFIX" ERROR: Wrong number of parameters ($# instead of 3)! Usage: service_action.sh event new-role cluster-name" >> $LOG_PATH/$LOG_NAME
    exit 1
fi

event=$1
newrole=$2
clustername=$3

if ! [[ "$event" =~ ^("on_start"|"on_stop"|"on_role_change")$ ]]; then
    echo $LOG_PREFIX" ERROR: Unknown event ($event)! Known ones: on_start, on_stop, on_role_change" >> $LOG_PATH/$LOG_NAME
    exit 1
fi

if ! [[ "$newrole" =~ ^("master"|"replica")$ ]]; then
    echo $LOG_PREFIX" ERROR: Unknown role ($newrole)! Known ones: master, replica" >> $LOG_PATH/$LOG_NAME
    exit 1
fi

echo $LOG_PREFIX" WARNING: Script started for event $event, new role $newrole for cluster $clustername" >> $LOG_PATH/$LOG_NAME

if [[ "$event" -eq "on_start" ]] || [[ "$event" -eq "on_role_change" && "$newrole" -eq "master" ]]; then
    echo $LOG_PREFIX" WARNING: Have to activate service for this conditions, executing now!" >> $LOG_PATH/$LOG_NAME
    ansible-playbook -i $ANSIBLE_PATH/inventory.yml $ANSIBLE_PATH/start-local.yml > $LOG_PATH/$ANSIBLE_LASTLOG
elif [[ "$event" -eq "on_stop" ]] || [[ "$event" -eq "on_role_change" && "$newrole" -eq "replica" ]]; then
    echo $LOG_PREFIX" WARNING: Have to activate service for this conditions, executing now!" >> $LOG_PATH/$LOG_NAME
    ansible-playbook -i $ANSIBLE_PATH/inventory.yml $ANSIBLE_PATH/stop-local.yml > $LOG_PATH/$ANSIBLE_LASTLOG
fi

exit 0
