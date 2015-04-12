#!/bin/bash
# Prompt for variables if they aren't already set
if [ -z "$controllerip" ]; then
    echo -n "Input Controller Server's Management IP: "
    read controllerip
fi

if [ -z "$pubip" ]; then
    echo -n "Input Controller Server's Public IP: "
    read pubip
fi

if [ -z "$glanceip" ]; then
    echo -n "Input Glance Server IP: "
    read glanceip
fi

if [ -z "$neutronip" ]; then
    echo -n "Input neutron Server IP: "
    read neutronip
fi

if [ -z "$neutronuserpass" ]; then
    echo -n "Input the neutron User's Keystone Password: "
    read neutronuserpass
fi

if [ -z "$neutrondbpass" ]; then
    echo -n "Input neutron's MySQL Database Password: "
    read neutrondbpass
fi

if [ -z "$novauserpass" ]; then
    echo -n "Input the Nova User's Keystone Password: "
    read novauserpass
fi

if [ -z "$novadbpass" ]; then
    echo -n "Input  Nova's MySQL Database Password: "
    read novadbpass
fi

if [ -z "$mgtiface" ]; then
    echo -n "Input the Management Interface: "
    read mgtiface
fi

if [ -z "$sharedsecret" ]; then
    echo -n "Input the Metadata Server's Shared Secret: "
    read sharedsecret
fi

# Set the Virtualizer here (Currently supports: kvm)
virt_type='kvm'


# Grab IP address of hte local management interface
localip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)


# Fix LVM so that cinder volumes don't cause performance issues
sed -i -e 's|filter = \[ \"a\/.*\/" \]|filter = [ "a/sda/", "a/sdb/", "r/.*/"]|' /etc/lvm/lvm.conf
