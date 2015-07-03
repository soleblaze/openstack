# Kilo OpenStack Installation Scripts

These scripts are designed to deploy Kilo OpenStack on Ubuntu 14.04.  They are for the initial installation of OpenStack.  They do not cover the creation of networks, projects, users, glance images, etc.  This will be done in the future in a how-to section.
  
These scripts are heavily influenced by the Folsom and Grizzly documentation created by [mseknibilel][msknibilel].  
You can find msknibilel's Grizzly install guide [here][grizzlyguide].

**Note: These scripts do not currently setup SSL or HA and therefore are not suitable for production environments.**


## Examples

[Multi-Node 2 NIC][MultiNode-2NIC] is an example of using these scripts to setup a cluster where one node is running Controller, Cinder, Glance, and Quantum and the other ndoes are running Compute.  Each node has 2 NICs.

## controller.sh

This script is designed to deploy the initial controller node.  This includes installing and setting up mysql, rabbitmq, keystone, nova (minus compute), and horizon.
This script will create a /root/.novarc file that you can source to import the credentials in order to run tools that talk to nova (such as nova and nova-manage)
This script will also output a set of bash commands that can be used to import passwords and IPs to be used with the other installation scripts.

## quantum.sh

This script is designed to deploy the Quantum server.  It can be deployed on its own server or on the controller node.  This script tends to kill network connections, which should come up properly after a reboot.  If you're running this from an ssh connection I suggest rebooting after the script by running this in screen:  
  
    ./quantum.sh && shutdown -r now  
  
You can also manually fix it by running:  
  
    ifconfig ${public interface} 0.0.0.0
    route add default gw ${gateway}

## glance.sh

This script is designed to deploy the Glance server.  If you do not have a separate data network then you should put the management network interface for the data interface.

## cinder.sh

This script is designed to deploy the Cinder server.  If you do not have a separate data network then you should put the management network interface for the data interface. You will need to create a LVM2 volume group named cinder-volumes in order to use this.

## compute.sh

This script is designed to deploy nova compute servers.  The controller.sh should spit out most of the variables needed for this.  If you are deploying this to multiple machines than I highly suggest hard coding the variables into the script and copying that to each compute server for deployment.


---
### Todo

* Give more Examples
* Add Swift support to controller.sh
* Create swift.sh
* Write a guide on creating floating IP address space
* Write a guide on creating networks
* Write a guide on creating users and projects
* Create a script to create multiple l3-agents for routing
* Create a script to download and add some basic images
* Create a guide to adding images
* Create a guide to creating images

[MultiNode-2NIC]:https://github.com/soleblaze/openstack/blob/master/examples/MultiNode-2NIC.md
[msknibilel]:https://github.com/mseknibilel/
[grizzlyguide]:https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide

