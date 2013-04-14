#!/bin/bash

echo -e "Input Data Interface: "
read dataiface
localip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -e "Input Controller IP [$dataiface]: "
read mgtip

if [ -z "$mgtip" ]; then
    mgtip=$localip
fi

if [ -z "$cinderuser" ]; then
    echo -e "Input Cinder Keystone User's Password: "
    read glanceuser
fi

if [ -z "$cinderdb" ]; then
    echo -e "Input Cinder MySQL Database's Password: "
    read glancedb
fi


# Add repos for grizzly if they don't already exist

if [ ! -e /etc/apt/sources.list.d/grizzly.list ]; then
    apt-get install ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
    apt-get update
fi

# Install Cinder

apt-get install -y cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms python-mysqldb

# Enable iSCSI Services

sed -i 's/false/true/g' /etc/default/iscsitarget
service iscsitarget start
service open-iscsi start

# Setup authentication

sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/cinder/api-paste.ini
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/cinder/api-paste.ini
sed -i -e "s/^admin_user.*/admin_user\ =\ quantum/" /etc/cinder/api-paste.ini
sed -i -e "s/^admin_password.*/admin_password\ =\ $quantumuser/" /etc/cinder/api-paste.ini
sed -i -e "s/^service_host.*/service_host\ =\ $localip/" /etc/cinder/api-paste.ini

# Setup database connection for Cinder

echo "sql_connection = mysql://cinderUser:$cinderdb@$mgtip/cinder" >> /etc/cinder/cinder.conf

# Lock Cinder down to the data port

echo "osapi_volume_listen=$localip" >> /etc/cinder/cinder.conf

# Update iSCSI Type for Cidner

sed -i -e "s/^iscsi_helper.*/iscsi_helper\ =\ ietadm/" /etc/cinder/cinder.conf

# Sync Cinder

cinder-manage db sync


# Restart Cinder

for service in cinder-api cinder-scheduler cinder-volume; do service $service restart; done

# done

echo "Cinder has been installed"
echo ""
echo "In order to use Cinder you will need to have a LVM2 Volume Group named cinder-volumes"
echo ""
echo "You can create this using the following commands.  Subsitute [DISK] for your the partition"
echo "you would like to use for this"
echo ""
echo "pvcreate /dev/[DISK]"
echo "lvcreate cinder-volumes /dev/[DISK]"
