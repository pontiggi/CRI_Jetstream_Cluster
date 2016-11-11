# Jetstream Cluster using Ansible

This playbook is designed for setting up an HPC-style cluster in the Jetstream cloud environment. Actual provisioning of VM's is done
via Heat scripts, available here [link]. 

In theory, this would work on bare metal as well, although it will not ease the pain of deploying CentOS 7 on many nodes, and you would need
to hand-generate a list of IP addresses (or modify this to run a dhcp server on the head node...).

#How To - by 'hand'
1. Get a working openrc.sh by following the Jetstream docs!

2. Install ansible,  or clone the repo and remember where the 
   environment variables script is.

3. Create an ssh keypair for use with Jetstream (Or re-use one!)

4. Add that key to your openstack account:
`source openrc.sh`
`nova keypair-add --pub-key /home/$username/.ssh/jetstream.pub jetstream_key`

5. Use the no\_torque.yml Heat script to create the VMs for your cluster: 
`openstack stack create --parameter key=jetstream_key -t ./no_torque.yml no_torque_stack`
(The name no\_torque\_stack is optional!)

6. Find the public ip of your new headnode, assuming the stack created
   successfully. Check creation status via:
`openstack stack show -c stack_status no_torque_stack`
  Find the public ip via:

7. Edit the following files to contain the correct ssh key and headnode
   ip: ssh.cfg and inventory/submits

7. Run the ansible playbook. 
   `ansible-playbook cluster.yml`

#How To - the Easy Way
1. Get a working openrc.sh by following the Jetstream docs!

2. Install ansible somehow.

3. Edit the first few lines of deploy.sh to point to your ssh key
   of choice, your ansible installation, your openrc.sh, and choose
   a name for your stack. You may also edit this to reflect the number
   of nodes!

4. Run deploy.sh, wait, ssh into your new cluster, and enjoy!
   See the file Cluster\_deploy.log or ssh.cfg for ip information.

#Roles

There are several roles here, which may be generally useful for some other things.

## Common

## Torque

## grid\_user

## postfix

## ssh\_and\_host\_keys

## xnit

## torque

## torque\_restart
