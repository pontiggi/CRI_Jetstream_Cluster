# Jetstream Cluster using Ansible

This playbook is designed for setting up an HPC-style cluster in the Jetstream cloud environment. Actual provisioning of VM's is done
via Heat scripts, in the heat-configs directory.

In theory, this would work on bare metal as well, although it will not ease the pain of deploying CentOS 7 on many nodes, and you would need
to hand-generate a list of IP addresses (or modify this to run a dhcp server on the head node...). 

The main variables for a new virtual clsuter are all set in 
the file "stack\_settings", which is used by deploy.sh. SSH
keys for outside users should be copied to the
roles/users/files/user\_keys directory.

#How To - by 'hand'
1. Get a working openrc.sh by following the Jetstream docs!
..+ *NOTE* : This playbook *requires* the heat module to be installed on the openstack cloud you are using! 
If you run into problems, check with `openstack catalog list` that your cloud has the right modules available. 

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

8. Run the ansible playbook. 
   `ansible-playbook cluster.yml`

#How To - the Easy Way
1. Get a working openrc.sh by following the Jetstream docs!

2. Install ansible somehow.

3. Edit the lines in stack\_settings to point to your ssh key
   of choice, your ansible installation, your openrc.sh, and choose
   a name for your stack. You may also edit this to reflect the number
   of nodes!

4. Run deploy.sh, wait, ssh into your new cluster, and enjoy!
   See the file Cluster\_deploy.log or ssh.cfg for ip information.

#IN CASE OF FAILURE (Or you just want to build anew)

1. Run destroy.sh and try again! 

#Upcoming Features

1. Scripts for adding/removing compute nodes

2. Fully elastic compute (dependent on 1.)

#Roles

There are several roles here, which may be generally useful for some other things.
Documentation on these will be forthcoming. A Slurm role is also in progress.

## Common
This role handles setup of things common across the nodes - installing
various utilities and common dependencies for scientific software,
configuring the nfs mounts (/home and /N are shared across all nodes),
and setting the hosts file correctly.

## Torque

This role builds and configures a basic Torque (PBS) resource manager
using the pbs\_sched scheduler, which is a basic 'first-in, first-out'
scheduler. RPMs are built on the head node, and installed on compute
nodes with this role.

### torque\_restart

This role just restarts the pbs\_server on the headnode after all 
compute nodes are reporting in.

## Slurm

This role provides a working, basic slurm installation, with 
FIFO scheduling and a single queue.

## users

The role reads from the users and admins list in stack\_settings,
populates the users ssh keys from roles/files/users/user\_keys,
and provides admins with sudo.

## xnit

This role installs and enables the XNIT repository.

## Applications

This role installs a variety of scientific applications - either
as a list, or a set of build steps. Currently only Quantum Espresso 
is present as a set of steps; other software is available through
the XNIT.

