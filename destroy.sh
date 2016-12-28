#!/bin/bash

#openrc_loc=./openrc.sh #openrc.sh file - see Jetstream docs!
#stack_name=$(grep 'stack_name=' deploy.sh | sed -e 's/.*"\(.*\)".*/\1/')

source ./stack_settings

source $openrc_loc

openstack stack delete $stack_name

stack_delete_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
until [[ $stack_delete_status != "DELETE_IN_PROGRESS" ]]; do
 echo "Deleting stack..."
 sleep 30
 stack_delete_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
done
