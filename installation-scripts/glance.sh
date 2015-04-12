#!/bin/bash
echo -n "Input Data Interface: "
read dataiface
localip=$(ip addr show $dataiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

if [ -z "$mgtip" ]; then
    echo -n "Input Controller IP [$localip]: "
    read mgtip
fi

if [ -z "$mgtip" ]; then
    mgtip=$localip
fi

if [ -z "$glanceuserpass" ]; then
    echo -e "Input Glance Keystone User's Password: "
    read glanceuserpass
fi

if [ -z "$glancedbpass" ]; then
    echo -e "Input Glance MySQL Database's Password: "
    read glancedbpass
fi

if [ -z "$rabbitpw" ]; then
    echo -e "Input RabbitMQ Password: "
    read rabbitpw
fi

# Add repos for juno if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-juno.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/juno main >> /etc/apt/sources.list.d/cloudarchive-juno.list
    apt-get update
fi

# Install glance
apt-get install -y glance python-glanceclient

# Setup /etc/glance/glance-api.conf
cat > /etc/glance/glance-api.conf < EOF
[DEFAULT]
notification_driver = messagingv2
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}

[database]
connection = mysql://glance:${glancedbpass}@${mgtip}/glance

[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = glance
admin_password = ${glanceuserpass}
 
[paste_deploy]
flavor = keystone

[glance_store]
default_store = file
filesystem_store_datadir = /var/lib/glance/images/
EOF

# Setup /etc/glance/glance-registry.conf
cat > /etc/glance/glance-registry.conf < EOF
[DEFAULT]
notification_driver = messagingv2
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}

[database]
connection = mysql://glance:${glancedbpass}@${mgtip}/glance

[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = glance
admin_password = ${glanceuserpass}
 
[paste_deploy]
flavor = keystone
EOF

# Restart glance
service glance-api restart
service glance-registry restart

# Sync glance database
su -s /bin/sh -c "glance-manage db_sync" glance

# Restart glance again
service glance-api restart
service glance-registry restart

# Delete uneeded sqlite file
rm -f /var/lib/glance/glance.sqlite

# Done
echo "Glance has been installed."
