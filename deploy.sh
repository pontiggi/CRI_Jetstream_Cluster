#!/bin/bash

#these should come in as mandatory args with 'sensible' defaults
openrc_loc=./openrc.sh #openrc.sh file - see Jetstream docs!
ssh_key=/home/jecoulte/.ssh/testkey.pub #ssh key for your nodes
ansible_loc=/home/jecoulte/Work/Tools/ansible/hacking/env-setup #ansible environment variables
deploy_log=./Cluster_deploy.log #log file - hopefully I've redirected everything to here.
#:%s/echo \(.*\)/echo \1 | tee -a $deploy_log/gc should allow you to fix that (in vim)
stack_name="test_stack" #name of the stack
declare -i number_of_nodes
number_of_nodes=4 #please don't make this anything other than an integer! It gets used in a regex below.
compute_inventory=inventory/computes
submit_inventory=inventory/submits

echo "Using openrc from: $openrc_loc" | tee $deploy_log
echo "Using ssh_key: $ssh_key" | tee -a $deploy_log
echo "Sourcing ansible variables from: $ansible_loc" | tee -a $deploy_log

#set the number of compute (non-head) nodes
sed -i "s/^    default: [0-9]\+/    default: $number_of_nodes/" heat-config/no_torque.yml

# use all nodes in test script
sed -i "s/nodes=[0-9]\+/nodes=$number_of_nodes/" roles/grid_user/files/node_query.job
# create inventory/computes...
#TODO

#check if $ANSIBLE_HOME gets set on pip install ansible, and test for that, before attempting to source!
#source $ansible_loc

#get openstack variables
# ASSUME THE USER HAS A WORKING openrc.sh 
source $openrc_loc

nova_result=$(nova keypair-add --pub-key $ssh_key jetstream_key 2>&1)
echo "Nova Result: $nova_result" >> $deploy_log

# if there is no error,  or the error is "key-pair already exists" then we are ok to continue; otherwise, print and exit
if [[ ! ${nova_result} != "" || ! ${nova_result} =~ .*already\ exists.* ]]; then
 echo "NOVA ERROR: $nova_result" | tee -a $deploy_log
 exit
fi

# current heat config has no shared volume due to acccount restricitons...
stack_exists=$(openstack stack list | grep $stack_name)
if [[ -z $stack_exists ]]; then 
 echo "Creating Stack!"
 openstack stack create --parameter key=jetstream_key -t ./heat-config/no_torque.yml $stack_name | tee -a $deploy_log
else
 echo "Stack exists: continuing."
fi

#need until loop - check every minute that the stack built or not:
stack_build_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')

until [[ $stack_build_status != "CREATE_IN_PROGRESS" ]]; do
  echo "Stack build in progress..." | tee -a $deploy_log
  sleep 60
  stack_build_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}')
done

if [[ $stack_build_status == "CREATE_FAILED" ]]; then
#this shouldn't just be a single field; output has spaces! :(
  failure_reason=$(openstack stack show -c stack_status_reason $stack_name | awk -F"|" '/status_reason/ {print $3}')
  echo "Stack create failed: $failure_reason" | tee -a $deploy_log
  echo "Removing failed stack! Please try again." | tee -a $deploy_log
  openstack stack delete $stack_name
  stack_delete_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}' 2>&1)
  until [[ $stack_delete_status != "DELETE_IN_PROGRESS" ]]; do
    echo "Deleting stack..."
    sleep 10
    stack_delete_status=$(openstack stack show -c stack_status $stack_name | awk '/stack_status/ {print $4}' 2>&1)
  done
  exit
fi

if [[ $stack_build_status == "CREATE_COMPLETE" ]]; then
  echo "Stack build Complete!" | tee -a $deploy_log
  headnode_id_hash=$(openstack stack resource list $stack_name | awk '/torque_server / {print $4}')
  headnode_ip=$(nova floating-ip-list | awk "/$headnode_id_hash/"'{print $4}')

  echo "Setting ip in ansible config files..." | tee -a $deploy_log
# replace ip address in ssh.cfg and inventory- now we have 10 problems!!! (possibly 11)
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" ssh.cfg
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" $submit_inventory
  echo "Headnode ip: $headnode_ip - testing ssh..." | tee -a $deploy_log

  ssh_hostname=$(ssh -F ssh.cfg $headnode_ip 'hostname' 2>&1 | tee -a $deploy_log) 
  if [[ ! $ssh_hostname =~ "torque-server" ]]; then
    echo "ssh connection to headnode Failed! Please try again." | tee -a $deploy_log
    echo "SSH ERROR: $ssh_hostname" | tee -a $deploy_log
    exit
  else
# test compute nodes and generate inventory file
    declare -i last_node=$number_of_nodes+4
    echo "Connection made to head node - testing computes now." | tee -a $deploy_log
    echo "[compute_nodes]" > $compute_inventory

    for i in $(seq 5 $last_node) 
    do
      ssh_compute=$(ssh -q -F ssh.cfg 10.0.0.$i 'hostname' 2>&1) 
      echo "Result of connecting to 10.0.0.$i : $ssh_compute" | tee -a $deploy_log
      if [[ ! $ssh_compute =~ 'compute-' ]]; then
        echo "Failed to connect! Check compute node build and try again." | tee -a $deploy_log 
        exit #fail hard if a node is broken
      fi
# add or correct entry in inventory file if needed
      if [[ $(grep $ssh_compute $compute_inventory) == "" ]]; then
        echo "$ssh_compute ansible_connection=ssh ansible_host=10.0.0.$i ansible_user=centos ansible_become=true become_method=sudo" >> $compute_inventory
      else
        sed -i "s/$ssh_compute\(.*\)=10.0.0.[0-9]\+\(.*\)/$ssh_compute\1=10.0.0.$i\2/" $compute_inventory
      fi 
    done
  fi
#HOPEFULLY THERE AREN'T OTHER OPTIONS FOR stack_status...
#Naturally, there are... but hopefully only these three after a CREATE

#Then, ansible-playbook (finally!)
source $ansible_loc

ansible-playbook -i inventory cluster.yml | tee -a $deploy_log
#ansible submit_nodes -i inventory -a "hostname"
fi

