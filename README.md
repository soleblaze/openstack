# Grizzly OpenStack Installation Scripts

These scripts are designed to deploy Grizzly OpenStack on Ubuntu 12.04.  
  
These scripts are heavily influenced by the Folsom and Grizzly documentation created by [mseknibilel][msknibilel].  
You can find msknibilel's Grizzly install guide [here][grizzlyguide]

**Note: These scripts do not currently setup SSL or HA and therefore are not suitable for production environments.**

## controller.sh

This script is designed to deploy the initial controller node.  This includes installing and setting up mysql, rabbitmq, keystone, nova (minus compute), and horizon.
This script will create a /root/.novarc file that you can source to import the credentials in order to run tools that talk to nova (such as nova and nova-manage)
This script will also output a set of bash commands that can be used to import passwords and IPs to be used with the other installation scripts.

## quantum.sh

This script is designed to deploy the Quantum server.  It can be deployed on its own server or on the controller node.  This script tends to kill network connections, which should come up properly after a reboot.  If you're running this from an ssh connection I suggest rebooting after the script by running this in screen:  
  
./quantum.sh && shutdown -r now  
  
You can also manually fix it by running:  
  
    ifconfig ${management interface} 0.0.0.0
    route add default gw ${gateway}

## glance.sh

This script is designed to deploy the Glance server.  If you do not have a separate data network then you should put the management network interface for the data interface.

## cinder.sh

This script is designed to deploy the Cinder server.  If you do not have a separate data network then you should put the management network interface for the data interface. You will need to create a LVM2 volume group named cinder-volumes in order to use this.

[msknibilel]:https://github.com/mseknibilel/
[grizzlyguide]:ttps://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide

