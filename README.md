# openstack

These scripts are currently designed to deploy OpenStack on Ubuntu 12.04.  

## controller.sh - Work in Progress

This script is designed to deploy the initial controller node.  This includes installing and setting up mysql, rabbitmq, keystone, nova (minus compute), and horizon.  
This script will create a /root/.novarc file that you can source to import the credentials in order to run tools that talk to nova (such as nova and nova-manage)  
This script will output a set of bash commands that can be used to import passwords and IPs to be used with the other installation scripts.
