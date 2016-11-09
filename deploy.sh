#!/bin/bash

#these should come in as mandatory args with 'sensible' defaults
openrc_loc=./openrc.sh
ssh_key=/home/jecoulte/.ssh/testkey.pub
ansible_loc=/home/jecoulte/Work/Tools/ansible/hacking/env-setup
deploy_log=./Cluster_deploy.log
stack_name="auto_stack" #temp name for testing

echo "Using openrc from: $openrc_loc"
echo "Using ssh_key: $ssh_key"
echo "Sourcing ansible variables from: $ansible_loc"

#check if $ANSIBLE_HOME gets set on pip install ansible, and test for that, before attempting to source!
#source $ansible_loc

#get openstack variables
# ASSUME THE USER HAS A WORKING openrc.sh 
source $openrc_loc

nova_result=$(nova keypair-add --pub-key $ssh_key jetstream_key 2>&1)

# if there is no error,  or the error is "key-pair already exists" then we are ok to continue; otherwise, print and exit
if [[ ! ${nova_result} != "" && ${nova_result} =~ .*already\ exists.* ]]; then
 echo "NOVA ERROR: $nova_result" | tee $deploy_log
 exit
fi

# current heat config has no shared volume due to acccount restricitons...
openstack stack create --parameter key=jetstream_key -t ./heat-config/no_torque.yml $stack_name | tee $deploy_log

#need until loop - check every minute that the stack built or not:
stack_build_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
until [[ $stack_build_status != "CREATE_IN_PROGRESS" ]]; do
  echo "Stack build in progress..."
  sleep 600
  stack_build_status=$(openstack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
done

if [[ $stack_build_status == "CREATE_FAILED" ]]; then
  failure_reason=$(openstack stack show -c stack_status_reason $stack_name)
  openstack stack delete $stack_name
  echo "Stack build failed. Please try again."
  echo $failure_reason
  exit
fi

if [[ $stack_build_status == "CREATE_COMPLETE" ]]; then
  echo "Stack build Complete! - Testing ssh access now..."
# something like this... but this thing is a mess to parse. Probably available via getting the
# instance id, and then calling nova floating-ip-list w/ grep for id. 
# openstack stack resource show auto_stack torque_server_public_ip  
fi

#openstack stack delete no_torque_stack
#Then, double check that ssh works for each node... only failure mode I've seen so far.

#THEN, get ips, setup files

#Then, ansible-playbook (finally!)

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

