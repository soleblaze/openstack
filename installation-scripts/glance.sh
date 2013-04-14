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

if [ -z "$glanceuser" ]; then
    echo -e "Input Glance Keystone User's Password: "
    read glanceuser
fi

if [ -z "$glancedb" ]; then
    echo -e "Input Glance MySQL Database's Password: "
    read glancedb
fi


# Add repos for grizzly if they don't already exist

if [ ! -e /etc/apt/sources.list.d/grizzly.list ]; then
    apt-get install ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
    apt-get update
fi

# Instal glance

apt-get install -y glance

# Setup authentication

echo "auth_host = $mgtip" >> /etc/glance/glance-api-paste.ini
echo "auth_port = 35357" >> /etc/glance/glance-api-paste.ini
echo "auth_protocol = http" >> /etc/glance/glance-api-paste.ini
echo "admin_tenant_name = service" >> /etc/glance/glance-api-paste.ini
echo "admin_user = glance" >> /etc/glance/glance-api-paste.ini
echo "admin_password = $glanceuser" >> /etc/glance/glance-api-paste.ini

# Setup database access

sed -i -e "s|^sql_connection.*|sql_connection\ =\ mysql://glanceUser:$glancedb@$mgtip/glance|" /etc/glance/glance-api.conf

# Setup glance registry authentication

echo "auth_host = $mgtip" >> /etc/glance/glance-registry-paste.ini
echo "auth_port = 35357" >> /etc/glance/glance-registry-paste.ini
echo "auth_protocol = http" >> /etc/glance/glance-registry-paste.ini
echo "admin_tenant_name = service" >> /etc/glance/glance-registry-paste.ini
echo "admin_user = glance" >> /etc/glance/glance-registry-paste.ini
echo "admin_password = $glanceuser" >> /etc/glance/glance-registry-paste.ini

# Setup glance registry database access

sed -i -e "s|^sql_connection.*|sql_connection\ =\ mysql://glanceUser:$glancedb@$mgtip/glance|" /etc/glance/glance-registry.conf
sed -i -e "s/^#flavor=/flavor\ =\ keystone/" /etc/glance/glance-registry.conf

# Setup glance api database access

sed -i -e "s|^sql_connection.*|sql_connection\ =\ mysql://glanceUser:$glancedb@$mgtip/glance|" /etc/glance/glance-api.conf
sed -i -e "s/^#flavor=/flavor\ =\ keystone/" /etc/glance/glance-api.conf

# Setup authtoken for glance-api

sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/glance/glance-api.conf
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/glance/glance-api.conf
sed -i -e "s/^admin_user.*/admin_user\ =\ glance/" /etc/glance/glance-api.conf
sed -i -e "s/^admin_password.*/admin_password\ =\ $glanceuser/" /etc/glance/glance-api.conf

# Setup authtoken for glance-registry

sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/glance/glance-registry.conf
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/glance/glance-registry.conf
sed -i -e "s/^admin_user.*/admin_user\ =\ glance/" /etc/glance/glance-registry.conf
sed -i -e "s/^admin_password.*/admin_password\ =\ $glanceuser/" /etc/glance/glance-registry.conf

# Restart glance

service glance-api restart
service glance-registry restart

# Sync glance database

glance-manage db_sync

# Restart glance again

service glance-api restart
service glance-registry restart

# Done

echo "Glance has been installed."
