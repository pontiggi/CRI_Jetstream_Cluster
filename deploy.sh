#!/bin/bash

#these should come in as mandatory args with 'sensible' defaults
openrc_loc=./openrc.sh
ssh_key=/home/jecoulte/.ssh/testkey.pub
ansible_loc=/home/jecoulte/Work/Tools/ansible/hacking/env-setup

echo "Using openrc from: $openrc_loc"
echo "Using ssh_key: $ssh_key"
echo "Sourcing ansible variables from: $ansible_loc"

#get openstack variables
source $openrc_loc

#GReat. The version of nova on my laptop is WAY old.
nova keypair-add --pub-key $ssh_key jetsteam_key

#maybe I should rename this no_torque stuff
#openstack stack create --parameter key=jetstream_key -t ./no_torque.yml no_torque_stack

#wait for the above to complete! ARGH - then get ip from cli.
# have a check that ssh will work...
#if !ssh $headnode_ip `hostname` then openstack-remove and repeat?
# or let the user handle that bit?
# openstack-remove would be nice.

#get IP, set up config files

#sed -i "s/headnode_ip/${headnode_ip}/" ssh.cfg
#sed -i "s/headnode_ip/${headnode_ip}/" inventory/submits

#echo "Headnode ip is: ${headnode_ip}" > Cluster_Info.txt

#NOT worrying about launching from a shell without ansible
# can also have option for script-only folks to source 
# ansible/setup/hacking-env

#ansible-playbook cluster.yml

#sed -i "s/headnode_ip/${headnode_ip}/" ssh.cfg
#sed -i "s/headnode_ip/${headnode_ip}/" inventory/submits

