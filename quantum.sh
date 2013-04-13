#!/bin/bash

echo -e "Input Management Interface: "
read mgtiface
localip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -e "Input Public Interface: "
read pubiface
pubip=$(ip addr show $pubiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -e "Input Controller IP [$localip]: "
read mgtip

if [ -z "$mgtip" ]; then
    mgtip=$localip
fi

if [ -z "$quantumuser" ]; then
    echo -e "Input Quantum Keystone User's Password: "
    read quantumuser
fi

if [ -z "$quantumdb" ]; then
    echo -e "Input Quantum MySQL Database's Password: "
    read quantumdb
fi

# Add repos for grizzly if they don't already exist

if [ ! -e /etc/apt/sources.list.d/grizzly.list ]; then
    apt-get install ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
    apt-get update
fi

# Install NTP
    
apt-get install -y ntp

# Install Network Services

apt-get install -y vlan bridge-utils

## install openvsswitch

apt-get install -y openvswitch-switch openvswitch-datapath-dkms
    
## Create bridges

ovs-vsctl add-br br-int
ovs-vsctl add-br br-ext

# Modify /etc/network/interfaces to keep ethernet port working

sed -i -e "s/$pubiface/br-ext/" /etc/network/interfaces

echo "" >> /etc/network/interfaces
echo "auto $pubiface" >> /etc/network/interfaces
echo "iface $pubiface inet manual" >> /etc/network/interfaces
echo -e "\tup ifconfig \$IFACE up" >> /etc/network/interfaces
echo -e "\tdown ifconfig \$IFACE down" >> /etc/network/interfaces

# Setup External VM access

ovs-vsctl br-set-external-id br-ext bridge-id br-ext
ovs-vsctl add-port br-ext $pubiface

# Restart networking

service networking restart

# Enable IP Forwarding

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl net.ipv4.ip_forward=1

# Install Quantum

apt-get install -y quantum-server quantum-plugin-openvswitch quantum-plugin-openvswitch-agent dnsmasq quantum-dhcp-agent quantum-l3-agent

# Setup authentication 

sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/quantum/api-paste.ini
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/quantum/api-paste.ini
sed -i -e "s/^admin_user.*/admin_user\ =\ quantum/" /etc/quantum/api-paste.ini
sed -i -e "s/^admin_password.*/admin_password\ =\ $quantumuser/" /etc/quantum/api-paste.ini

sed -i -e "s/keystoneclient.middleware.auth_token:filter_factory/keystoneclient.middleware.auth_token:filter_factory\nauth_host = $mgtip\nauth_port = 35357\nauth_protocol = http\nadmin_tenant_name = service\nadmin_user = quantum\nadmin_password = $quantumuser/" /etc/quantum/api-paste.ini

# Setup OVS Plugin Configuration

sed -i -e "s|^sql_connection.*|sql_connection\ =\ mysql://quantumUser:$quantumdb@$mgtip/quantum|" /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

sed -i -e "s|^\[OVS\]|\[OVS\]\ntenant_network_type\ =\ gre\ntunnel_id_ranges\ =\ 1:1000\nintegration_bridge\ =\ br-int\ntunnel_bridge\ =\ br-tun\nlocal_ip\ =\ $localip\nenable_tunneling\ =\ True|"  /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

# Setup l3_agent authentication

echo "auth_url = http://$mgtip:35357/v2.0" >> /etc/quantum/l3_agent.ini
echo "auth_region = RegionOne" >> /etc/quantum/l3_agent.ini
echo "admin_tenant_name = service" >> /etc/quantum/l3_agent.ini
echo "admin_user = quantum" >> /etc/quantum/l3_agent.ini
echo "admin_password = $quantumuser" >> /etc/quantum/l3_agent.ini

# Setup metadata l3_agent

sed -i -e "s|^auth_url.*|auth_url\ =\ http://$mgtip:35357/v2.0|" /etc/quantum/metadata_agent.ini
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/quantum/metadata_agent.ini
sed -i -e "s/^admin_user.*/admin_user\ =\ quantum/" /etc/quantum/metadata_agent.ini
sed -i -e "s/^admin_password.*/admin_password\ =\ $quantumuser/" /etc/quantum/metadata_agent.ini
sed -i -e "s/#\ metadata_proxy_shared_secret.*/metadata_proxy_shared_secret\ =\ $sharedsecret/" /etc/quantum/metadata_agent.ini
sed -i -e "s/#\ nova_metadata_ip.*/nova_metadata_ip\ =\ $localip/" /etc/quantum/metadata_agent.ini
sed -i -e 's/#\ \(nova_metadata_port.*\)/\1/'  /etc/quantum/metadata_agent.ini

# Enable namespaces with the dhcp agent

sed -i -e "s/#\ use_namespaces.*/use_namespaces\ =\ True/" /etc/quantum/dhcp_agent.ini

# Give quantum sudo access for running ip in order to fix some errors that show in the logs

echo "" >> /etc/sudoers
echo "# This is to fix errors that quantum generates" >> /etc/sudoers
echo "quantum ALL = NOPASSWD: /sbin/ip" >> /etc/sudoers

## Restart quantum Services

for service in quantum-dhcp-agent quantum-l3-agent quantum-metadata-agent quantum-plugin-openvswitch-agent quantum-server dnsmasq; do service $service restart; done

# Report Sucess

echo "Quantum should now be installed and working."
