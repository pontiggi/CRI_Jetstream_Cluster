# Jetstream Cluster using Ansible

This playbook is designed for setting up an HPC-style cluster in the Jetstream cloud environment. Actual provisioning of VM's is done
via Heat scripts, available here [link]. 

In theory, this would work on bare metal as well, although it will not ease the pain of deploying CentOS 7 on many nodes, and you would need
to hand-generate a list of IP addresses (or modify this to run a dhcp server on the head node...).

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
