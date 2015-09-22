#!/bin/bash

echo -n "Input Data Interface: "
read dataiface
localip=$(ip addr show $dataiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -n "Input Management Interface: "
read mgtiface
cindermgtip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

if [ -z "$mgtip" ]; then
    echo -n "Input Controller IP [$localip]: "
    read mgtip
fi

if [ -z "$mgtip" ]; then
    mgtip=$localip
fi

if [ -z "$cinderuserpass" ]; then
    echo -e "Input Cinder Keystone User's Password: "
    read cinderuserpass
fi

if [ -z "$cinderdbpass" ]; then
    echo -e "Input Cinder MySQL Database's Password: "
    read cinderdbpass
fi

if [ -z "$rabbitpw" ]; then
    echo -e "Input RabbitMQ Password: "
    read rabbitpw
fi

# Add repos for kilo if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-kilo.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/kilo main >> /etc/apt/sources.list.d/cloudarchive-kilo.list
    apt-get update
fi


# Install Cinder
apt-get install -y cinder-volume python-mysqldb qemu lvm2

# Set up LVM filter to prevent performance issues relating to cinder lvms
sed -i -e 's|filter = \[ \"a\/.*\/" \]|filter = [ "a/sda/", "a/sdb/", "r/.*/"]|' /etc/lvm/lvm.conf

cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = tgtadm
volume_name_template = volume-%s
volume_group = cinder-volumes
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
control_exchange = cinder
notification_driver = messagingv2
rpc_backend = rabbit
auth_strategy = keystone
my_ip = ${cindermgtip}
glance_host = ${mgtip}
enabled_backends = lvm

[oslo_messaging_rabbit]
rabbit_host = ${mgtip}
rabbit_userid = openstack
rabbit_password = ${rabbitpw}

[oslo_concurrency]
lock_path = /var/lock/cinder

[database]
connection = mysql://cinderUser:${cinderdbpass}@${mgtip}/cinder

[keystone_authtoken]
auth_uri = http://${mgtip}:5000
auth_url = http://${mgtip}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = cinder
password = ${cinderuserpass}

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
iscsi_protocol = iscsi
iscsi_helper = tgtadm
EOF

# Restart Services
service tgt restart
service cinder-volume restart

rm -f /var/lib/cinder/cinder.sqlite

