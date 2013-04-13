#!/bin/bash

# Disable Interactive apt-get in order to prevent mysql from prompting for a password
export DEBIAN_FRONTEND=noninteractive

# Get Setup Info from User

echo -n "Input Management Interface: "
read mgtiface
mgtip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)


echo -n "Input Public Interface: "
read pubiface
pubip=$(ip addr show $pubiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)

echo -n "Input Admin Password: "
read ADMIN_PASSWORD

echo -n "Input MySQL Root Password: "
read MYSQL_PASSWORD

echo -n "Input Cinder IP [${mgtip}]: "
read cinderip

if [ -z "$cinderip" ]; then
    cinderip=$mgtip
fi

echo -n "Input Glance IP [${mgtip}]: "
read glanceip

if [ -z "$glanceip" ]; then
    glanceip=$mgtip
fi
echo -n "Input EC2 IP [${mgtip}]: "
read ec2ip

if [ -z "$ec2ip" ]; then
    ec2ip=$mgtip
fi

echo -n "Input Quantum IP [${mgtip}]: "
read quantumip

if [ -z "$quantumip" ]; then
    quantumip=$mgtip
fi

# Generate Random passwords for database accounts

keystonedb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
glancedb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
quantumdb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
novadb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
cinderdb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)

# Generate Random passwords for keystone accounts

novauser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
glanceuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
quantumuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
cinderuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)

# Generate Shared Secret for Quantum Metadata SErver

sharedsecret=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)

# Add repos for grizzly

apt-get install -y ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring
echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
apt-get update

# Install mysql

apt-get install -y mysql-server python-mysqldb
sed -i "s/127.0.0.1/$mgtip/g" /etc/mysql/my.cnf
mysqladmin -u root password "$MYSQL_PASSWORD"
service mysql restart

# Setup databases

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE keystone;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON keystone.* TO 'keystoneUser'@'%' IDENTIFIED BY '${keystonedb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE glance;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON glance.* TO 'glanceUser'@'%' IDENTIFIED BY '${glancedb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE quantum;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON quantum.* TO 'quantumUser'@'%' IDENTIFIED BY '${quantumdb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE nova;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY '${novadb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE cinder;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON cinder.* TO 'cinderser'@'%' IDENTIFIED BY '${cinderdb}';"

# Install RabbitMQ

apt-get install -y rabbitmq-server

# Install ntp

apt-get install -y ntp


# Enable IP Forwarding

sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl net.ipv4.ip_forward=1

# Install keystone

apt-get install -y keystone

# Setup keystone.conf

sed -i -e "s|^connection.*|connection\ =\ mysql://keystoneUser:${keystonedb}@${mgtip}/keystone|" /etc/keystone/keystone.conf
sed -i -e 's/^#token_format.*/token_format\ =\ UUID/' /etc/keystone/keystone.conf

# Restart Keystone and Sync the service

service keystone restart
keystone-manage db_sync

# Setup Keystones basic configuration
# Taken from https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/blob/OVS_MultiNode/KeystoneScripts/keystone_basic.sh

## Set Variables for keystone

export ADMIN_PASSWORD
export SERVICE_TOKEN="ADMIN"
export SERVICE_ENDPOINT="http://$mgtip:35357/v2.0"
export SERVICE_TENANT_NAME=service


## Create a function to grab the id
get_id () {
    echo `$@ | awk '/ id / { print $4 }'`
}

## Tenants
ADMIN_TENANT=$(get_id keystone tenant-create --name=admin)
SERVICE_TENANT=$(get_id keystone tenant-create --name=service)

## Admin User
ADMIN_USER=$(get_id keystone user-create --name=admin --pass="$ADMIN_PASSWORD" --email=admin@domain.com)

## Roles
ADMIN_ROLE=$(get_id keystone role-create --name=admin)
KEYSTONEADMIN_ROLE=$(get_id keystone role-create --name=KeystoneAdmin)
KEYSTONESERVICE_ROLE=$(get_id keystone role-create --name=KeystoneServiceAdmin)

## Add Roles to Users in Tenants
keystone user-role-add --user-id $ADMIN_USER --role-id $ADMIN_ROLE --tenant-id $ADMIN_TENANT
keystone user-role-add --user-id $ADMIN_USER --role-id $KEYSTONEADMIN_ROLE --tenant-id $ADMIN_TENANT
keystone user-role-add --user-id $ADMIN_USER --role-id $KEYSTONESERVICE_ROLE --tenant-id $ADMIN_TENANT

## The Member role is used by Horizon and Swift
MEMBER_ROLE=$(get_id keystone role-create --name=Member)

## Configure service users/roles
NOVA_USER=$(get_id keystone user-create --name=nova --pass="$novauser" --tenant-id $SERVICE_TENANT --email=nova@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $NOVA_USER --role-id $ADMIN_ROLE

GLANCE_USER=$(get_id keystone user-create --name=glance --pass="glanceuser" --tenant-id $SERVICE_TENANT --email=glance@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $GLANCE_USER --role-id $ADMIN_ROLE

QUANTUM_USER=$(get_id keystone user-create --name=quantum --pass="$quantumuser" --tenant-id $SERVICE_TENANT --email=quantum@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $QUANTUM_USER --role-id $ADMIN_ROLE

CINDER_USER=$(get_id keystone user-create --name=cinder --pass="$cinderuser" --tenant-id $SERVICE_TENANT --email=cinder@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $CINDER_USER --role-id $ADMIN_ROLE

# Setup Endpoints for Openstack
# Taken from https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/blob/OVS_MultiNode/KeystoneScripts/keystone_endpoints_basic.sh

MYSQL_USER=keystoneUser
MYSQL_HOST=$mgtip
MYSQL_DATABASE=keystone

## Create Services

keystone service-create --name nova --type compute --description 'OpenStack Compute Service'
keystone service-create --name cinder --type volume --description 'OpenStack Volume Service'
keystone service-create --name glance --type image --description 'OpenStack Image Service'
keystone service-create --name keystone --type identity --description 'OpenStack Identity'
keystone service-create --name ec2 --type ec2 --description 'OpenStack EC2 service'
keystone service-create --name quantum --type network --description 'OpenStack Networking service'

## Create Endpoints

create_endpoint () {
  case $1 in
    compute)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8774/v2/$(tenant_id)s' --adminurl 'http://'"$mgtip"':8774/v2/$(tenant_id)s' --internalurl 'http://'"$mgtip"':8774/v2/$(tenant_id)s'
    ;;
    volume)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$cinderip"':8776/v1/$(tenant_id)s' --adminurl 'http://'"$cinderip"':8776/v1/$(tenant_id)s' --internalurl 'http://'"$cinderip"':8776/v1/$(tenant_id)s'
    ;;
    image)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$glanceip"':9292/v2' --adminurl 'http://'"$glanceip"':9292/v2' --internalurl 'http://'"$glanceip"':9292/v2'
    ;;
    identity)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':5000/v2.0' --adminurl 'http://'"$mgtip"':35357/v2.0' --internalurl 'http://'"$mgtip"':5000/v2.0'
    ;;
    ec2)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$ec2ip"':8773/services/Cloud' --adminurl 'http://'"$ec2ip"':8773/services/Admin' --internalurl 'http://'"$ec2ip"':8773/services/Cloud'
    ;;
    network)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$quantumip"':9696/' --adminurl 'http://'"$quantumip"':9696/' --internalurl 'http://'"$quantumip"':9696/'
    ;;
  esac
}

for i in compute volume image object-store identity ec2 network; do
  id=`mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$keystonedb" "$MYSQL_DATABASE" -ss -e "SELECT id FROM service WHERE type='"$i"';"` || exit 1
  create_endpoint $i $id
done

# Create credentials file 

echo export OS_TENANT_NAME=admin > /root/.novarc
echo export OS_USERNAME=admin >> /root/.novarc
echo export OS_PASSWORD="$ADMIN_PASSWORD" >> /root/.novarc
echo export OS_AUTH_URL="http://$mgtip:5000/v2.0/" >> /root/.novarc

# Install nova

apt-get install -y nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor 

# Set keystone auth info in /etc/nova/api-paste.ini

sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_user.*/admin_user\ =\ nova/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_password.*/admin_password\ =\ $novauser/" /etc/nova/api-paste.ini

# Create nova.conf file

rm /etc/nova/nova.conf

cat > /etc/nova/nova.conf << EOF
[DEFAULT]
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
verbose=True
api_paste_config=/etc/nova/api-paste.ini
compute_scheduler_driver=nova.scheduler.simple.SimpleScheduler
rabbit_host=$mgtip
nova_url=http://$mgtip:8774/v1.1/
sql_connection=mysql://novaUser:$novauser@$mgtip/nova
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
vncserver_proxyclient_address=$mgtip
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

#Metadata
service_quantum_metadata_proxy = True
quantum_metadata_proxy_shared_secret = $sharedsecret
metadata_host = $quantumip
metadata_listen = $quantumip
metadata_listen_port = 8775

# Compute #
compute_driver=libvirt.LibvirtDriver

# Cinder #
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900
EOF

## Sync nova database

nova-manage db sync

## Install Novaclient python tools

apt-get install -y python-novaclient

# Install Horizon

apt-get install -y openstack-dashboard memcached

# Disable offline compression 

sed -i -e 's/COMPRESS_OFFLINE\ =\ True/COMPRESS_OFFLINE\ =\ False/' /etc/openstack-dashboard/local_settings.py

# Restart apache2 and memcached

service apache2 restartservice memcached restart

# Echo out passwords for future Setup

echo "These are the variables needed for the rest of the installation:"
echo ""
echo "export mgtip=$mgtip"
echo "export cinderip=$cinderip"
echo "export glanceip=$glanceip"
echo "export ec2ip=$ec2ip"
echo "export quantumip=$quantumip"
echo "export keystonedb=$keystonedb"
echo "export glancedb=$glancedb"
echo "export quantumdb=$quantumdb"
echo "export novadb=$novadb"
echo "export cinderdb=$cinderdb"
echo "export novauser=$novauser"
echo "export glanceuser=$glanceuser"
echo "export quantumuser=$quantumuser"
echo "export cinderuser=$cinderuser"
echo "export sharedsecret=$sharedsecret"
echo ""

echo "For using nova commands you need to source /root/.novarc first."
