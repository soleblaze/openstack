#!/bin/bash

# You Can Uncomment These to Hard Code Variables Here for Easier Deployment

# Controller Server's Management IP
# controllerip="172.16.0.2"

# Controller Server's Public IP
# pubip="192.168.1.2"

# Glance Server's IP
# glanceip="172.16.0.2"

# Quantum Server's IP
# quantumip="172.16.0.2"

# Quantum Keystone Password
# quantumuser=quantum_keystone_pass

# Quantum Database Password
# quantumdb=quantum_pass

# Nova Keystone Password
# novauser=nova_keystone_pass

# Nova Database Password
# novadb=nova_pass

# Metadata Server's Shared Secret
# sharedsecret="helloOpenStack"

# Management Network interface
# mgtiface=eth1

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

if [ -z "$quantumip" ]; then
    echo -n "Input Quantum Server IP: "
    read quantumip
fi

if [ -z "$quantumuser" ]; then
    echo -n "Input the Quantum User's Keystone Password: "
    read quantumuser
fi

if [ -z "$quantumdb" ]; then
    echo -n "Input Quantum's MySQL Database Password: "
    read quantumdb
fi

if [ -z "$novauser" ]; then
    echo -n "Input the Nova User's Keystone Password: "
    read novauser
fi

if [ -z "$novadb" ]; then
    echo -n "Input  Nova's MySQL Database Password: "
    read novadb
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


# Add repos for grizzly if they don't already exist

if [ ! -e /etc/apt/sources.list.d/grizzly.list ]; then
    apt-get install -y ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
    apt-get update
fi

# Install NTP

apt-get install -y ntp


# Install Bridge Utils

apt-get install -y vlan bridge-utils


# Enable IP Forwarding

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl net.ipv4.ip_forward=1

# If KVM is used, check to verify that hardware support is turned on.

if [ "$virt_type" = "kvm" ]; then
    apt-get install -y cpu-checker

    if [ -z "$(kvm-ok | grep 'KVM acceleration can be used')" ]; then
        echo "ERROR: KVM support is not enabled."
        exit 1
    fi

    # Install nova compute

    apt-get install -y nova-compute-kvm pm-utils

    # Enable cgroup_device_acl for libvirt

    sed -i -e 's|#cgroup_device_acl.*|cgroup_device_acl = [\
"/dev/null", "/dev/full", "/dev/zero",\
"/dev/random", "/dev/urandom",\
"/dev/ptmx", "/dev/kvm", "/dev/kqemu",\
"/dev/rtc", "/dev/hpet","/dev/net/tun"\
]"\
#cgroup_device_acl = [\n|' /etc/libvirt/qemu.conf

    # Delete default virtual bridge

    virsh net-destroy default
    virsh net-undefine default

    # Setup Authentication information for nova

    sed -i -e "s/^auth_host.*/auth_host\ =\ $controllerip/" /etc/nova/api-paste.ini
    sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/nova/api-paste.ini
    sed -i -e "s/^admin_user.*/admin_user\ =\ nova/" /etc/nova/api-paste.ini
    sed -i -e "s/^admin_password.*/admin_password\ =\ $novauser/" /etc/nova/api-paste.ini

    # Setup Nova Compute configuration

    rm /etc/nova/nova-compute.conf

    cat > /etc/nova/nova-compute.conf << EOF
[DEFAULT]
libvirt_type=kvm
libvirt_ovs_bridge=br-int
libvirt_vif_type=ethernet
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
libvirt_use_virtio_for_bridges=True
EOF

    # Setup nova.conf

    rm /etc/nova/nova.conf

    cat > /etc/nova/nova.conf << EOF
[DEFAULT]
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
verbose=True
api_paste_config=/etc/nova/api-paste.ini
compute_scheduler_driver=nova.scheduler.simple.SimpleScheduler
rabbit_host=$controllerip
nova_url=http://$controllerip:8774/v1.1/
sql_connection=mysql://novaUser:$novadb@$mgtip/nova
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf

# Auth
use_deprecated_auth=false
auth_strategy=keystone

# Imaging service
glance_api_servers=$glanceip:9292
image_service=nova.image.glance.GlanceImageService

# Vnc configuration
novnc_enabled=true
novncproxy_base_url=http://$pubip:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=$controllerip
vncserver_listen=0.0.0.0

# Network settings
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$quantumip:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=service
quantum_admin_username=quantum
quantum_admin_password=$quantumuser
quantum_admin_auth_url=http://$quantumip:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver

# Metadata
service_quantum_metadata_proxy = True
quantum_metadata_proxy_shared_secret = $sharedsecret
metadata_host = $quantumip
metadata_listen = 127.0.0.1
metadata_listen_port = 8775

# Compute
compute_driver=libvirt.LibvirtDriver

# Cinder
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900
EOF

    # Restart Nova-Compute

    service nova-compute restart




else
    echo "ERROR: This script currently only supports KVM."
    exit 2
fi

# Install OpenVSwitch

apt-get install -y openvswitch-switch openvswitch-datapath-dkms

# Create bridge for instance integration

ovs-vsctl add-br br-int

# Install Quantum openvswitch agent

apt-get -y install quantum-plugin-openvswitch-agent

# Setup Quantum openvswitch quantum-plugin-openvswitch-agent

sed -i -e "s|^sql_connection.*|sql_connection\ =\ mysql://quantumUser:$quantumdb@$controllerip/quantum|" /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

sed -i -e "s|^\[OVS\]|\[OVS\]\n\
tenant_network_type\ =\ gre\n\
tunnel_id_ranges\ =\ 1:1000\n\
integration_bridge\ =\ br-int\n\
tunnel_bridge\ =\ br-tun\n\
local_ip\ =\ $localip\n\
enable_tunneling\ =\ True\n|"  /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

# Set RabbitMQ Server for Quantum

sed -i -e "s/#\ rabbit_host.*/rabbit_host\ =\ $controllerip/" /etc/quantum/quantum.conf

# Restart Quantum openvswitch agent

service quantum-plugin-openvswitch-agent restart

