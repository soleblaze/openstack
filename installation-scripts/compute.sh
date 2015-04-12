#!/bin/bash
# Prompt for variables if they aren't already set
if [ -z "$controllerip" ]; then
    echo -n "Input Controller Server's Management IP: "
    read controllerip
fi

if [ -z "$tunip" ]; then
    echo -n "Input Compute Server Tunnel IP: "
    read tunip
fi

if [ -z "$pubip" ]; then
    echo -n "Input Controller Server's Public IP: "
    read pubip
fi

if [ -z "$controllerfqdn" ]; then
    echo -n "Input Controller Server's FQDN: "
    read controllerfqdn
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

if [ -z "$rabbitpw" ]; then
    echo -n "Input RabbitMQ Password: "
    read rabbitpw
fi

if [ -z "$ceilometersecret" ]; then
    echo -n "Input Ceilometer Secret: "
    read ceilometersecret
fi

if [ -z "$ceilometeruserpass" ]; then
    echo -n "Input Ceilometer Password: "
    read ceilometeruserpass
fi

if [ -z "$KEYSTONE_REGION" ]; then
    KEYSTONE_REGION=RegionOne
fi

# Grab IP address of hte local management interface
localip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

# Fix LVM so that cinder volumes don't cause performance issues
sed -i -e 's|filter = \[ \"a\/.*\/" \]|filter = [ "a/sda/", "a/sdb/", "r/.*/"]|' /etc/lvm/lvm.conf

# Add repos for juno if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-juno.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/juno main >> /etc/apt/sources.list.d/cloudarchive-juno.list
    apt-get update
fi

# Install nova
apt-get install -y nova-compute sysfsutils

# Setup /etc/nova/nova.conf
cp /etc/nova/nova.conf /root/nova.bak
cat > /etc/nova/nova.conf << EOF
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
libvirt_use_virtio_for_bridges=True
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
enabled_apis=ec2,osapi_compute,metadata
rpc_backend = rabbit
rabbit_host = $controllerip
rabbit_userid = openstack
rabbit_password = $rabbitpw
auth_strategy = keystone
my_ip = $localip
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = $localip
novncproxy_base_url = http://${controllerfqdn}:6080/vnc_auto.html
network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver
instance_usage_audit = True
instance_usage_audit_period = hour
notify_on_state_change = vm_and_task_state
notification_driver = messagingv2

[keystone_authtoken]
auth_uri = http://$controllerip:5000/v2.0
identity_uri = http://$controllerip:35357
admin_tenant_name = service
admin_user = nova
admin_password = $novauserpass

[glance]
host = $glanceip

[neutron]
url = http://${controllerip}:9696
auth_strategy = keystone
admin_auth_url = http://${controllerip}:35357/v2.0
admin_tenant_name = service
admin_username = neutron
admin_password = ${neutronuserpass}
EOF

# Setup sysctl
echo 'net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0' > /etc/sysctl.d/20-ipforward.conf
sysctl -p

# Install Networking Components
apt-get install -y neutron-plugin-ml2 neutron-plugin-openvswitch-agent


## Setup /etc/neutron/neutron.conf
cp /etc/neutron/neutron.conf /root/neutron.bak
cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
lock_path = \$state_path/lock
auth_strategy = keystone
rpc_backend = rabbit
rabbit_host=${controllerip}
rabbit_userid=openstack
rabbit_password=${rabbitpw}
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True

[matchmaker_redis]

[matchmaker_ring]

[quotas]

[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf
[keystone_authtoken]
auth_uri = http://${controllerip}:5000/v2.0
identity_uri = http://${controllerip}:35357
admin_tenant_name = service
admin_user = neutron
admin_password = $neutronuser

[database]

[service_providers]
service_provider=LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
service_provider=VPN:openswan:neutron.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default
EOF

# Setup /etc/neutron/plugins/ml2/ml2_conf.ini
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,gre
tenant_network_types = gre
mechanism_drivers = openvswitch

[ml2_type_flat]
tunnel_id_ranges = 1:1000

[ml2_type_vlan]

[ml2_type_gre]

[ml2_type_vxlan]

[securitygroup]
enable_security_group = True
enable_ipset = True
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[ovs]
local_ip = ${tunip}
enable_tunneling = True

[agent]
tunnel_types = gre
EOF

# Restart networking
service openvswitch-switch restart
service nova-compute restart
service neutron-plugin-openvswitch-agent restart

# Install Ceilometer
apt-get install -y ceilometer-agent-compute


# Setup /etc/ceilometer/ceilometer.conf
cp /etc/ceilometer/ceilometer.conf /root/ceilometer.bak
cat > /etc/ceilometer/ceilometer.conf << EOF
[DEFAULT]
log_dir=/var/log/ceilometer
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${controllerip}
rabbit_password = ${rabbitpw}
auth_strategy = keystone

[alarm]

[api]

[central]

[collector]

[compute]

[coordination]

[database]

[dispatcher_file]

[event]

[hardware]

[ipmi]

[keystone_authtoken]
auth_uri = http://${controllerip}:5000/v2.0
identity_uri = http://${controllerip}:35357
admin_tenant_name = service
admin_user = ceilometer
admin_password = ${ceilometeruserpass}

[matchmaker_redis]

[matchmaker_ring]

[notification]

[publisher]
metering_secret = ${ceilometersecret}

[publisher_notifier]

[publisher_rpc]

[service_credentials]
os_auth_url = http://${controllerip}:5000/v2.0
os_username = ceilometer
os_tenant_name = service
os_password = ${ceilometeruserpass}
os_endpoint_type = internalURL
os_region_name = ${KEYSTONE_REGION}

[service_types]

[vmware]

[xenapi]
EOF

# Restart ceilometer
service ceilometer-agent-compute restart
