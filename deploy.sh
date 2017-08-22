#!/bin/bash

source ./stack_settings

#--------------------------------------------------------
# NOTHING BELOW THIS SHOULD BE EDITED BY HAND 
#(unless errors are encountered)
#--------------------------------------------------------
compute_inventory=inventory/computes
submit_inventory=inventory/submits

echo "Using openrc from: $openrc_loc" | tee $deploy_log
echo "Using ssh_key: $ssh_key" | tee -a $deploy_log
echo "Sourcing ansible variables from: $ansible_loc" | tee -a $deploy_log

#set the number of compute (non-head) nodes
sed -i "s/^    default: [0-9]\+/    default: $number_of_nodes/" heat-config/no_torque.yml
sed -i "s/\(\s\+number_of_nodes:\)\s\+[0-9]\+/\1 $number_of_nodes/" group_vars/all

# use all nodes in test script
sed -i "s/nodes=[0-9]\+/nodes=$number_of_nodes/" roles/users/files/torque_example.job

# add users to group_vars/all
#remove old user list
sed -i '/users:/,$d' $vars_file

echo "  users:" >> $vars_file
for user in $users 
do 
 echo "   - $user" >> $vars_file
done

echo "  admins:" >> $vars_file
for admin in $admins
do
 echo "   - $admin" >> $vars_file
done

#check if $ANSIBLE_HOME gets set on pip install ansible, and test for that, before attempting to source!
#source $ansible_loc

#get openstack variables
# ASSUME THE USER HAS A WORKING openrc.sh 
source $openrc_loc

key_create_result=$(openstack keypair create --public-key $ssh_key new_jetstream_key 2>&1)
echo "Key creation Result: $key_create_result" >> $deploy_log

# if there is no error,  or the error is "key-pair already exists" then we are ok to continue; otherwise, print and exit
if [[ ! ${key_create_result} != "" || ! ${key_create_result} =~ .*already\ exists.* ]]; then
 echo "OPENSTACK ERROR: $key_create_result" | tee -a $deploy_log
 exit
fi

#check if global-ssh security group exists:
sec_group_check=$(openstack security group list | grep "global-ssh")
if [[ -z $sec_group_check ]]; then
  echo "creating global-ssh security group!"
  openstack security group create --description "ssh & icmp enabled" global-ssh
  openstack security group rule create --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0 global-ssh
  openstack security group rule create --protocol icmp global-ssh
else
  echo "global-ssh security group exists!"
fi

# current heat config has no shared volume due to acccount restricitons...
stack_exists=$(openstack stack list | grep $stack_name)
if [[ -z $stack_exists ]]; then 
 echo "Creating Stack!"
 openstack stack create --parameter key=new_jetstream_key -t ./heat-config/no_torque.yml $stack_name | tee -a $deploy_log
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
  headnode_id_hash=$(openstack stack resource list $stack_name | awk '/slurm-server / {print $4}')
  headnode_ip=$(openstack stack output show $stack_name public_ip | awk '/output_value/ {print $4}')
  headnode_private_ip=$(openstack stack output show $stack_name private_ip | awk '/output_value/ {print $4}')

  echo "Setting ip in ansible config files..." | tee -a $deploy_log
# replace ip address in ssh.cfg and inventory- now we have 10 problems!!! (possibly 11)
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" ssh.cfg
  sed -i "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$headnode_ip/" $submit_inventory
# set headnode in group_vars/all
  sed -i "s/\(\s\+headnode_ip:\).*/\1 $headnode_ip/" group_vars/all
  echo "Headnode ip: $headnode_ip - testing ssh..." | tee -a $deploy_log

  ssh_hostname=$(ssh -F ssh.cfg $headnode_ip 'hostname' 2>&1 | tee -a $deploy_log) 
  if [[ ! $ssh_hostname =~ "slurm-server" ]]; then
    echo "ssh connection to headnode Failed! Please try again." | tee -a $deploy_log
    echo "SSH ERROR: $ssh_hostname" | tee -a $deploy_log
    exit
  else
# test compute nodes and generate inventory file
    declare -i last_node=$number_of_nodes-1
    echo "Connection made to head node - testing computes now." | tee -a $deploy_log
    echo "[compute_nodes]" > $compute_inventory

    for i in $(seq 0 $last_node) 
    do
      compute_ip=$(openstack server show compute-$i | awk '/addresses/ {print $4}' | cut -d'=' -f 2)
      ssh_compute=$(ssh -q -F ssh.cfg $compute_ip 'hostname' 2>&1) 
      echo "Result of connecting to $compute_ip : $ssh_compute" | tee -a $deploy_log
      if [[ ! $ssh_compute =~ 'compute-' ]]; then
        echo "Failed to connect! Check compute node build and try again." | tee -a $deploy_log 
        exit #fail hard if a node is broken
      fi
# add or correct entry in inventory file if needed
      if [[ $(grep $ssh_compute $compute_inventory) == "" ]]; then
        echo "$ssh_compute ansible_connection=ssh ansible_host=$compute_ip ansible_user=centos ansible_become=true become_method=sudo" >> $compute_inventory
      else
        sed -i "s/$ssh_compute\(.*\)=10.0.0.[0-9]\+\(.*\)/$ssh_compute\1=$compute_ip\2/" $compute_inventory
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

