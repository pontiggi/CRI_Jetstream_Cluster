#!/bin/bash

source ./openrc.sh

for host in $(scontrol show hostname $0)
do
openstack server resume $host
done

pdsh 'sudo systemctl restart ntpd' $0
pdsh 'sudo systemctl restart slurmd' $0
