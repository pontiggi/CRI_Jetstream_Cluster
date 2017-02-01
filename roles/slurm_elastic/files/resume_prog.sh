#!/bin/bash

source ./openrc.sh

for host in $(scontrol show hostname $0)
do
openstack server suspend $host
done
