#!/bin/bash

#these should come in as mandatory args with 'sensible' defaults
openrc_loc=./openrc.sh #openrc.sh file - see Jetstream docs!
ssh_key=/home/jecoulte/.ssh/testkey.pub #ssh key for your nodes
ansible_loc=/home/jecoulte/Work/Tools/ansible/hacking/env-setup #ansible environment variables
deploy_log=./Cluster_deploy.log #log file - hopefully I've redirected everything to here.
#:%s/echo \(.*\)/echo \1 | tee -a $deploy_log/gc should allow you to fix that (in vim)
stack_name="auto_stack" #name of the stack
declare -i number_of_nodes
number_of_nodes=4 #please don't make this anything other than an integer! It gets used in a regex below.

echo "Using openrc from: $openrc_loc" | tee $deploy_log
echo "Using ssh_key: $ssh_key" | tee -a $deploy_log
echo "Sourcing ansible variables from: $ansible_loc" | tee -a $deploy_log

#set the number of compute (non-head) nodes
sed -i "s/^    default: [0-9]\+/    default: $number_of_nodes/" heat-config/no_torque.yml

#check if $ANSIBLE_HOME gets set on pip install ansible, and test for that, before attempting to source!
#source $ansible_loc

#get openstack variables
# ASSUME THE USER HAS A WORKING openrc.sh 
source $openrc_loc

nova_result=$(nova keypair-add --pub-key $ssh_key jetstream_key 2>&1)

# if there is no error,  or the error is "key-pair already exists" then we are ok to continue; otherwise, print and exit
if [[ ! ${nova_result} != "" && ${nova_result} =~ .*already\ exists.* ]]; then
 echo "NOVA ERROR: $nova_result" | tee -a $deploy_log
 exit
fi

# current heat config has no shared volume due to acccount restricitons...
#COMMENT OUT FOR TESTING BEHAVIOUR WITHOUT REBUILDING
#openstack stack create --parameter key=jetstream_key -t ./heat-config/no_torque.yml $stack_name | tee -a $deploy_log

#need until loop - check every minute that the stack built or not:
stack_build_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')

until [[ $stack_build_status != "CREATE_IN_PROGRESS" ]]; do
  echo "Stack build in progress..." | tee -a $deploy_log
  sleep 60
  stack_build_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
  echo "test: $stack_build_status" | tee -a $deploy_log
done

if [[ $stack_build_status == "CREATE_FAILED" ]]; then
  failure_reason=$(openstack stack show -c stack_status_reason $stack_name | awk '/status_reason/ {print $4}')
  echo "Stack create failed: $failure_reason" | tee -a $deploy_log
  echo "Removing failed stack! Please try again." | tee -a $deploy_log
  openstack stack delete $stack_name
  exit
fi

if [[ $stack_build_status == "CREATE_COMPLETE" ]]; then
  echo "Stack build Complete! - Testing ssh access now..." | tee -a $deploy_log
  headnode_id_hash=$(openstack stack resource list auto_stack | awk '/torque_server / {print $4}')
  headnode_ip=$(nova floating-ip-list | awk "/$headnode_id_hash/"'{print $4}')
  echo "Setting ip in ansible config files..." | tee -a $deploy_log
# using a regex to replace ip address - now we have 10 problems!!! (possibly 11)
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" ssh.cfg
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" inventory/submits
  echo "Headnode ip: $headnode_ip - testing ssh..." | tee -a $deploy_log
  ssh_hostname=$(ssh -F ssh.cfg $headnode_ip 'hostname' 2>&1) 
  if [[ $ssh_hostname != "torque-server" ]]; then
    echo "ssh connection to headnode Failed! Please try again." | tee -a $deploy_log
    echo "SSH ERROR: $ssh_hostname" | tee -a $deploy_log
    exit
  else
    echo "Connection made to head node - testing computes now." | tee -a $deploy_log
    declare -i last_node=$number_of_nodes+4
    for i in $(seq 5 $last_node) 
    do
      ssh_compute=$(ssh -q -F ssh.cfg 10.0.0.$i 'hostname' 2>&1) 
      echo "Result of connecting to 10.0.0.$i : $ssh_compute" | tee -a $deploy_log
      if [[ ! $ssh_compute =~ 'compute-' ]]; then
        echo "Failed to connect! Check compute node build and try again." | tee -a $deploy_log
      fi
    done
  fi
fi

#HOPEFULLY THERE AREN'T OTHER OPTIONS FOR stack_status...
#Naturally, there are... but hopefully only these three after a CREATE

#Then, ansible-playbook (finally!)
source $ansible_loc
# I bet tee breaks ansible again...
ansible-playbook -i inventory cluster.yml | tee -a $deploy_log
#ansible submit_nodes -i inventory -a "hostname"
