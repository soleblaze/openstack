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
    read glanceuserpass
fi

if [ -z "$cinderdbpass" ]; then
    echo -e "Input Cinder MySQL Database's Password: "
    read glancedbpass
fi

# Add repos for juno if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-juno.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/juno main >> /etc/apt/sources.list.d/cloudarchive-juno.list
    apt-get update
fi


# Install Cinder
apt-get install -y cinder-volume python-mysqldb

cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}
auth_strategy = keystone
my_ip = ${cindermgtip}
glance_host = ${mgtip}

[database]
connection = mysql://cinder:${cinderdbpass}@${mgtip}/cinder

[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = cinder
admin_password = ${cinderuserpass}
EOF

# Restart Services
service tgt restart
service cinder-volume restart

rm -f /var/lib/cinder/cinder.sqlite
