#!/bin/bash
echo -n "Input Neutron Network Interface: "
read mgtiface
localip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -n "Input Tunnel Network Interface: "
read tuniface
tunip=$(ip addr show $tuniface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -n "Input External Interface: "
read extiface

if [ -z "$mgtip" ]; then
    echo -n "Input Controller IP [$localip]: "
    read mgtip
fi

if [ -z "$mgtip" ]; then
    mgtip=$localip
fi

if [ -z "$neutronuserpass" ]; then
    echo -e "Input Neutron Keystone User's Password: "
    read neutronuserpass
fi

if [ -z "$neutrondbpass" ]; then
    echo -e "Input Neutron MySQL Database's Password: "
    read neutrondbpass
fi

if [ -z "$KEYSTONE_REGION" ]; then
    KEYSTONE_REGION=RegionOne
fi

# Get Shared Secret for Neutron Metadata Server
if [ -z "$sharedsecret" ]; then
    echo -e "Input Neutron Shared Secret: "
    read sharedsecret
fi

# Get RabbitMQ Password
if [ -z "$rabbitpw" ]; then
    echo -e "Input RabbitMQ: "
    read rabbitpw
fi

if [ -z "$neutronvlan" ]; then
    echo -n "Enter VLAN range if using (otherwise press enter): "
    read neutronvlan
fi


# Add repos for kilo if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-kilo.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/kilo main >> /etc/apt/sources.list.d/cloudarchive-kilo.list
    apt-get update
fi

# Install NTP
apt-get install -y ntp

# Install neutron
apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent \
neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent

# Setup sysctl for ip forwarding
echo 'net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0' > /etc/sysctl.d/20-ipforward.conf
sysctl -p

## Setup /etc/neutron/neutron.conf

cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True
auth_strategy = keystone
rpc_backend = rabbit

[oslo_messaging_rabbit]
rabbit_host = ${mgtip}
rabbit_userid = openstack
rabbit_password = ${rabbitpw}

[oslo_concurrency]
lock_path = \$state_path/lock

[matchmaker_redis]

[matchmaker_ring]

[quotas]

[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

[keystone_authtoken]
auth_uri = http://${mgtip}:5000
auth_url = http://${mgtip}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $neutronuserpass

[database]

[service_providers]
service_provider=LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
service_provider=VPN:openswan:neutron.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default
EOF

## Setup /etc/neutron/plugins/ml2/ml2_conf.ini
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,vlan,gre,vxlan
tenant_network_types = gre
mechanism_drivers = openvswitch

[ml2_type_flat]
flat_networks = external

[ml2_type_vlan]

[ml2_type_gre]
tunnel_id_ranges = 1:1000

[ml2_type_vxlan]

[securitygroup]
enable_security_group = True
enable_ipset = True
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[ovs]
local_ip = ${tunip}
enable_tunneling = True
bridge_mappings = external:br-ex

[agent]
tunnel_types = gre
EOF

## Setup /etc/neutron/l3_agent.ini
cat > /etc/neutron/l3_agent.ini << EOF
[DEFAULT]
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
use_namespaces = True
external_network_bridge = 
router_delete_namespaces = True
EOF


## Setup /etc/neutron/dhcp_agent.ini
cat > /etc/neutron/dhcp_agent.ini << EOF
[DEFAULT]
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
dhcp_delete_namespaces = True
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf
dnsmasq_dns_servers = 8.8.8.8
EOF

# Set MTU to 1454 to work around GRE issues
# This can be removed if jumbo frames are enabled
echo "dhcp-option-force=26,1454" > /etc/neutron/dnsmasq-neutron.conf

## Setup /etc/neutron/metadata_agent.ini
cat > /etc/neutron/metadata_agent.ini << EOF
[DEFAULT]
auth_uri = http://${mgtip}:5000
auth_url = http://${mgtip}:35357
auth_region = RegionOne
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = ${neutronuserpass}
nova_metadata_ip = ${mgtip}
metadata_proxy_shared_secret = ${sharedsecret}
EOF

if [ "$neutronvlan" ]; then
    sed -i -e 's|^type_drivers = flat,gre|type_drivers = flat,gre,vlan|' /etc/neutron/plugins/ml2/ml2_conf.ini
    sed -i -e "s|\[ml2_type_vlan\]|[ml2_type_vlan]\nnetwork_vlan_ranges = external:$neutronvlan|" /etc/neutron/plugins/ml2/ml2_conf.ini
    echo 'enable_isolated_metadata = True' >> /etc/neutron/dhcp_agent.ini
    sed -i -e 's|external_network_bridge = br-ex|external_network_bridge =|' /etc/neutron/l3_agent.ini  
fi 

## Configure external bridge
service openvswitch-switch restart
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex ${extiface}

# Restart Services
service neutron-plugin-openvswitch-agent restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
