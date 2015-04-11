#!/bin/bash

# Disable Interactive apt-get in order to prevent mysql from prompting for a password
export DEBIAN_FRONTEND=noninteractive

# Get Setup Info from User

if [ -z "$mgtip" ]; then
    echo -n "Input Management Interface: "
    read mgtiface
    mgtip=$(ip addr show $mgtiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)
fi


if [ -z "$pubip" ]; then
    echo -n "Input Public Interface: "
    read pubiface
    pubip=$(ip addr show $pubiface | awk '/inet\ / { print $2 }' | cut -d"/" -f1)
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    echo -n "Input Admin Password: "
    read ADMIN_PASSWORD
fi

if [ -z "$MYSQL_PASSWORD" ]; then
    echo -n "Input MySQL Root Password: "
    read MYSQL_PASSWORD
fi

if [ -z "$cinderip" ]; then
    echo -n "Input Cinder IP [${mgtip}]: "
    read cinderip

    if [ -z "$cinderip" ]; then
        cinderip=$mgtip
    fi
fi

if [ -z "$glanceip" ]; then
    echo -n "Input Glance IP [${mgtip}]: "
    read glanceip

    if [ -z "$glanceip" ]; then
        glanceip=$mgtip
    fi
fi

if [ -z "$neutronip" ]; then
    echo -n "Input Neutron IP [${mgtip}]: "
    read neutronip

    if [ -z "$neutronip" ]; then
    neutronip=$mgtip
    fi
fi

# Generate Random passwords for database accounts

if [ -z "$keystonedb" ]; then
    keystonedb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$ceilometerdb" ]; then
    ceilometerdb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$cinderdb" ]; then
    cinderdb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$glancedb" ]; then
    glancedb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$heatdb" ]; then
    heatdb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$neutrondb" ]; then
    neutrondb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$novadb" ]; then
    novadb=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi

# Generate Random passwords for keystone accounts

if [ -z "$ceilometeruser" ]; then
    ceilometeruser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$cinderuser" ]; then
    cinderuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$glanceuser" ]; then
    glanceuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$heatuser" ]; then
    heatuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$neutronuser" ]; then
    neutronuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$novauser" ]; then
    novauser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi
if [ -z "$neutronuser" ]; then
    neutronuser=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi

# Generate rabbit password
if [ -z "$rabbitpw" ]; then
    rabbitpw=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi

# Generate admin token
if [ -z "$keystonetoken" ]; then
    keystonetoken=$(openssl rand -hex 10)
fi

# Generate Shared Secret for Neutron Metadata Server

if [ -z "$sharedsecret" ]; then
    sharedsecret=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi

# Add repos for grizzly if they don't already exist

if [ ! -e /etc/apt/sources.list.d/cloudarchive-juno.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/juno main >> /etc/apt/sources.list.d/cloudarchive-juno.list
    apt-get update
fi

# Install mysql

apt-get install -y mariadb-server python-mysqldb
sed -i "s/127.0.0.1/$mgtip/g" /etc/mysql/my.cnf
awk '/.*InnoDB related.*/{print $0 RS \
"default-storage-engine = innodb" RS \
"innodb_file_per_table" RS \
"collation-server = utf8_general_ci" RS \
"init-connect = '\''SET NAMES utf8'\''" RS \
"character-set-server = utf8";next}1' /etc/mysql/my.cnf > /tmp/my.cnf
mv /tmp/my.cnf /etc/mysql/my.cnf
service mysql restart

# Runs same queries that mysql_secure_installation does
mysqladmin -u root password "$MYSQL_PASSWORD"
mysql -u root <<-EOF
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

# Setup databases

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE keystone;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON keystone.* TO 'keystoneUser'@'%' IDENTIFIED BY '${keystonedb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE glance;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON glance.* TO 'glanceUser'@'%' IDENTIFIED BY '${glancedb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE neutron;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON neutron.* TO 'neutronUser'@'%' IDENTIFIED BY '${neutrondb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE nova;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY '${novadb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE cinder;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON cinder.* TO 'cinderUser'@'%' IDENTIFIED BY '${cinderdb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE ceilometer;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON ceilometer* TO 'ceilometerUser'@'%' IDENTIFIED BY '${ceilometerdb}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE heat;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON heat* TO 'heatUser'@'%' IDENTIFIED BY '${heatdb}';"

# Install RabbitMQ
apt-get install -y rabbitmq-server

# Setup RabbitMQ openstack user
rabbitmqctl delete_user guest
rabbitmqctl add_user openstack ${rabbitpw}
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
service rabbitmq-server restart

# Install ntp
apt-get install -y ntp

# Install keystone
apt-get install -y keystone python-keystoneclient

# Setup keystone.conf

sed -i -e "s|^#admin_token.*|admin_token=${keystonetoken}|" /etc/keystone/keystone.conf
sed -i -e "s|^#provider.*|provider = keystone.token.providers.uuid.Provider|" /etc/keystone/keystone.conf
sed -i -e "s|^#driver=keystone.token.persistence.backends.sql.Token|driver = keystone.token.persistence.backends.sql.Token|" /etc/keystone/keystone.conf
sed -i -e "s|^#driver=keystone.contrib.revoke.backends.kvs.Revoke|driver = keystone.contrib.revoke.backends.sql.Revoke|" /etc/keystone/keystone.conf
sed -i -e "s|^connection.*|connection\ =\ mysql://keystoneUser:${keystonedb}@${mgtip}/keystone|" /etc/keystone/keystone.conf


# Sync and restart the keystone service
su -s /bin/sh -c "keystone-manage db_sync" keystone
service keystone restart

# Delete uneeded sqlite file
rm -f /var/lib/keystone/keystone.db

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

GLANCE_USER=$(get_id keystone user-create --name=glance --pass="$glanceuser" --tenant-id $SERVICE_TENANT --email=glance@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $GLANCE_USER --role-id $ADMIN_ROLE

NEUTRON_USER=$(get_id keystone user-create --name=neutron --pass="$neutronuser" --tenant-id $SERVICE_TENANT --email=neutron@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $NEUTRON_USER --role-id $ADMIN_ROLE

CINDER_USER=$(get_id keystone user-create --name=cinder --pass="$cinderuser" --tenant-id $SERVICE_TENANT --email=cinder@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $CINDER_USER --role-id $ADMIN_ROLE

HEAT_USER=$(get_id keystone user-create --name=heat --pass="$heatuser" --tenant-id $SERVICE_TENANT --email=heat@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $HEAT_USER --role-id $ADMIN_ROLE
Vjj
CEILOMETER_USER=$(get_id keystone user-create --name=ceilometer --pass="$ceilometeruser" --tenant-id $SERVICE_TENANT --email=cinder@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $CEILOMETER_USER --role-id $ADMIN_ROLE

# Setup Endpoints for Openstack
# Taken from https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/blob/OVS_MultiNode/KeystoneScripts/keystone_endpoints_basic.sh

export MYSQL_USER=keystoneUser
export MYSQL_DATABASE=keystone
if [ -z "$KEYSTONE_REGION" ]; then
    export KEYSTONE_REGION=RegionOne
fi

## Create Services

keystone service-create --name nova --type compute --description 'OpenStack Compute'
keystone service-create --name cinder --type volume --description 'OpenStack Block Storage'
keystone service-create --name cinderv2 --type volumev2 --description 'OpenStack Block Storage'
keystone service-create --name glance --type image --description 'OpenStack Image Service'
keystone service-create --name keystone --type identity --description 'OpenStack Identity'
keystone service-create --name neutron --type network --description 'OpenStack Networking'
keystone service-create --name heat --type orchestration --description 'Orchestration'
keystone service-create --name heat-cfn --type cloudformation --description 'Orchestration'
keystone service-create --name ceilometer --type metering --description 'Telemetry'
keystone service-create --name keystone --type identity --description 'OpenStack Identity'

## Create Endpoints

create_endpoint () {
  case $1 in
    compute)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s' --adminurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s' --internalurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s'
    ;;
    volume)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$cinderip"':8776/v1/%(tenant_id)s' --adminurl 'http://'"$cinderip"':8776/v1/%(tenant_id)s' --internalurl 'http://'"$cinderip"':8776/v1/%(tenant_id)s'
    ;;
    volumev2)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --adminurl 'http://'"%cinderip"':8776/v2/%(tenant_id)s' --internalurl 'http://'"%cinderip"':8776/v2/%(tenant_id)s'
    ;;
    image)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$glanceip"':9292/v2' --adminurl 'http://'"$glanceip"':9292/v2' --internalurl 'http://'"$glanceip"':9292/v2'
    ;;
    identity)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':5000/v2.0' --adminurl 'http://'"$mgtip"':35357/v2.0' --internalurl 'http://'"$mgtip"':5000/v2.0'
    ;;
    orchestration)
        keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"'::8004/v1/%(tenant_id)s' --adminurl 'http://'"$mgtip"':8004/v1/%(tenant_id)' --internalurl 'http://'"$mgtip"'::8004/v1/%(tenant_id)'
    ;;
    cloudformation)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8000/v1' --adminurl 'http://'"$mgtip"'8000/v1' --internalurl 'http://'"$mgtip"':800/v1'
    ;;
    metering)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8777' --adminurl 'http://'"$mgtip"':8777' --internalurl 'http://'"$mgtip"':8777'
    ;;
    network)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$neutronip"':9696/' --adminurl 'http://'"$neutronip"':9696/' --internalurl 'http://'"$neutronip"':9696/'
    ;;
  esac
}

for i in compute volume volumev2 image orchestration cloudformation metering identity network; do
  id=`mysql -h $mgtip -u "$MYSQL_USER" -p"$keystonedb" "$MYSQL_DATABASE" -ss -e "SELECT id FROM service WHERE type='"$i"';"` || exit 1
  create_endpoint $i $id
done

# Create credentials file 
echo export OS_TENANT_NAME=admin > /root/.novarc
echo export OS_USERNAME=admin >> /root/.novarc
echo export OS_PASSWORD="$ADMIN_PASSWORD" >> /root/.novarc
echo export OS_AUTH_URL="http://$mgtip:5000/v2.0/" >> /root/.novarc

# Install nova
apt-get install -y nova-api nova-cert nova-conductor nova-consoleauth \
nova-novncproxy nova-scheduler python-novaclient

# Set keystone auth info in /etc/nova/api-paste.ini
sed -i -e "s/^auth_host.*/auth_host\ =\ $mgtip/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_tenant_name.*/admin_tenant_name\ =\ service/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_user.*/admin_user\ =\ nova/" /etc/nova/api-paste.ini
sed -i -e "s/^admin_password.*/admin_password\ =\ $novauser/" /etc/nova/api-paste.ini

# Create nova.conf file
rm /etc/nova/nova.conf

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
connection = mysql://novaUser:$novadb@$mgtip/nova
rpc_backend = rabbit
rabbit_host = $mgtip
rabbit_password = $rabbitpw
auth_strategy = keystone
my_ip = $mgtip
vncserver_listen = $mgtip
vncserver_proxyclient_address = $mgtip

[keystone_authtoken]
auth_uri = http://$mgtip:5000/v2.0
identity_uri = http://$mgtip:35357
admin_tenant_name = service
admin_user = novaUser
admin_password = $novauser

[glance]
host = $glanceip
EOF

## Sync nova database

su -s /bin/sh -c "nova-manage db sync" nova

# Delete unneeded sqlite file
rm -f /var/lib/nova/nova.sqlite

## Restart nova services

for service in nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler; do service $service restart; done

# TODO: Have not updated past here for juno
# Install Horizon

apt-get install -y openstack-dashboard memcached

# Disable offline compression 

sed -i -e 's/COMPRESS_OFFLINE\ =\ True/COMPRESS_OFFLINE\ =\ False/' /etc/openstack-dashboard/local_settings.py

# Restart apache2 and memcached

service apache2 restart
service memcached restart

# Echo out passwords for future Setup
if [ -z "$silent" ]; then
    echo "This information should be kept in a safe place:"
    echo ""
    echo "Controller Server IP: $mgtip"
    echo "Public IP: $pubip"
    echo "Cinder Server IP: $cinderip"
    echo "Glance Server IP: $glanceip"
    echo "Neutron Server IP: $neutronip"
    echo ""
    echo "Cinder MySQL Database Password: $cinderdb"
    echo "Glance MySQL Database Password: $glancedb"
    echo "Nova MySQL Database Password: $novadb"
    echo "Keystone MySQL Database Password: $keystonedb"
    echo "Neutron MySQL Database Password: $neutrondb"
    echo ""
    echo "Cinder Keystone User Password: $cinderuser"
    echo "Glance Keystone User Password: $glanceuser"
    echo "Nova Keystone User Password: $novauser"
    echo "Neutron Keystone User Password: $neutronuser"
    echo ""
    echo "Neutron Metadata Server's Shared Secret: $sharedsecret"
    echo ""

    echo ""
    echo "For installing the Cinder Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export cinderuser=$cinderuser"
    echo "export cinderdb=$cinderdb"
    echo ""

    echo ""
    echo "For installing the Glance Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export glanceuser=$glanceuser"
    echo "export glancedb=$glancedb"
    echo ""

    echo ""
    echo "For installing the Neutron Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export neutronuser=$neutronuser"
    echo "export neutrondb=$neutrondb"
    echo ""

    echo ""
    echo "For installing a Compute Server you can export the following variables:"
    echo ""
    echo "export controllerip=$mgtip"
    echo "export pubip=$pubip"
    echo "export glanceip=$glanceip"
    echo "export neutronip=$neutronip"
    echo "export neutronuser=$neutronuser"
    echo "export neutrondb=$neutrondb"
    echo "export novauser=$novauser"
    echo "export novadb=$novadb"
    echo "export sharedsecret=$sharedsecret"
    echo "export rabbitpw=$rabbitpw"
    echo "export keystonetoken=$keystonetoken"
    echo ""

    echo ""
    echo "For using nova commands you need to source /root/.novarc first."
fi
