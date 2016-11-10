#!/bin/bash

openrc_loc=./openrc.sh #openrc.sh file - see Jetstream docs!
stack_name=$(grep 'stack_name=' deploy.sh | sed -e 's/.*"\(.*\)".*/\1/')

echo "source $openrc_loc"

echo "openstack stack delete $stack_name"
