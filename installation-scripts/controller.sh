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

if [ -z "$ADMIN_EMAIL" ]; then
    echo -n "Input Admin Email Address: "
    read ADMIN_EMAIL
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
if [ -z "$cinderdbpass" ]; then
    cinderdbpass=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
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
if [ -z "$cinderuserpass" ]; then
    cinderuserpass=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
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

# Generate ceilometer secret
if [ -z "$ceilometersecret" ]; then
    ceilometersecret=$(openssl rand -hex 10)
fi

# Generate Shared Secret for Neutron Metadata Server
if [ -z "$sharedsecret" ]; then
    sharedsecret=$(cat /dev/urandom| tr -dc 'a-zA-Z0-9'|fold -w 20 | head -n1)
fi

# Add repos for juno if they don't already exist
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
mysql -u root -p${MYSQL_PASSWORD} <<-EOF
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
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON cinder.* TO 'cinderUser'@'%' IDENTIFIED BY '${cinderdbpass}';"

mysql -uroot -p${MYSQL_PASSWORD} -e "CREATE DATABASE heat;"
mysql -uroot -p${MYSQL_PASSWORD} -e "GRANT ALL ON heat.* TO 'heatUser'@'%' IDENTIFIED BY '${heatdb}';"

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

# Setup cron to purge tokens hourly
(crontab -l -u keystone 2>&1 | grep -q token_flush) || \
echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' \
>> /var/spool/cron/crontabs/keystone

# Setup Keystones basic configuration
# Taken from https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/blob/OVS_MultiNode/KeystoneScripts/keystone_basic.sh

## Set Variables for keystone
export OS_SERVICE_TOKEN=${keystonetoken}
export OS_SERVICE_ENDPOINT=http://${mgtip}:35357/v2.0

## Create a function to grab the id
get_id () {
    echo `$@ | awk '/ id / { print $4 }'`
}

## Pause for 5 seconds so keystone has a chance to completely start
sleep 5

## Tenants
ADMIN_TENANT=$(get_id keystone tenant-create --name=admin)
SERVICE_TENANT=$(get_id keystone tenant-create --name=service)

## Admin User
ADMIN_USER=$(get_id keystone user-create --name=admin --pass="$ADMIN_PASSWORD" --email="${ADMIN_EMAIL}")

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

CINDER_USER=$(get_id keystone user-create --name=cinder --pass="$cinderuserpass" --tenant-id $SERVICE_TENANT --email=cinder@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $CINDER_USER --role-id $ADMIN_ROLE

HEAT_USER=$(get_id keystone user-create --name=heat --pass="$heatuser" --tenant-id $SERVICE_TENANT --email=heat@domain.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $HEAT_USER --role-id $ADMIN_ROLE
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
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --adminurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --internalurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s'
    ;;
    image)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$glanceip"':9292/v2' --adminurl 'http://'"$glanceip"':9292/v2' --internalurl 'http://'"$glanceip"':9292/v2'
    ;;
    identity)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':5000/v2.0' --adminurl 'http://'"$mgtip"':35357/v2.0' --internalurl 'http://'"$mgtip"':5000/v2.0'
    ;;
    orchestration)
        keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8004/v1/%(tenant_id)s' --adminurl 'http://'"$mgtip"':8004/v1/%(tenant_id)' --internalurl 'http://'"$mgtip"':8004/v1/%(tenant_id)'
    ;;
    cloudformation)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8000/v1' --adminurl 'http://'"$mgtip"'8000/v1' --internalurl 'http://'"$mgtip"':800/v1'
    ;;
    metering)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':8777' --adminurl 'http://'"$mgtip"':8777' --internalurl 'http://'"$mgtip"':8777'
    ;;
    network)
    keystone endpoint-create --region $KEYSTONE_REGION --service-id $2 --publicurl 'http://'"$mgtip"':9696/' --adminurl 'http://'"$mgtip"':9696/' --internalurl 'http://'"$mgtip"':9696/'
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
rabbit_userid = openstack
rabbit_password = $rabbitpw
auth_strategy = keystone
my_ip = $mgtip
vncserver_listen = $mgtip
vncserver_proxyclient_address = $mgtip

[keystone_authtoken]
auth_uri = http://$mgtip:5000/v2.0
identity_uri = http://$mgtip:35357
admin_tenant_name = service
admin_user = nova
admin_password = $novauser

[glance]
host = $glanceip

[neutron]
service_metadata_proxy = True
metadata_proxy_shared_secret = ${sharedsecret}
EOF

## Restart nova services
for service in nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler; do service $service restart; done

## Delete unneeded sqlite file
rm -f /var/lib/nova/nova.sqlite

## Install neutron
apt-get install -y neutron-server neutron-plugin-ml2 python-neutronclient

## Setup /etc/neutron/neutron.conf

cat > /etc/neutron/neutron.conf << EOF
[DEFAULT]
lock_path = \$state_path/lock
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True
auth_strategy = keystone
rpc_backend = rabbit
rabbit_host=${mgtip}
rabbit_userid=openstack
rabbit_password=${rabbitpw}
notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True
nova_url = http://${mgtip}:8774/v2
nova_admin_auth_url = http://${mgtip}:35357/v2.0
nova_region_name = ${KEYSTONE_REGION}
nova_admin_username = nova
nova_admin_tenant_id = ${SERVICE_TENANT}
nova_admin_password = ${novauser}
[matchmaker_redis]
[matchmaker_ring]
[quotas]
[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf
[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = neutron
admin_password = $neutronuser
[database]
connection = mysql://neutronUser:${neutrondb}@${mgtip}/neutron
[service_providers]
service_provider=LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
service_provider=VPN:openswan:neutron.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default
EOF

## Setup /etc/neutron/plugins/ml2/ml2_conf.ini
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,gre
tenant_network_types = gre
mechanism_drivers = openvswitch
[ml2_type_flat]
[ml2_type_vlan]
[ml2_type_gre]
tunnel_id_ranges = 1:1000
[ml2_type_vxlan]
[securitygroup]
enable_security_group = True
enable_ipset = True
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
EOF

# Populate database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
--config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade juno" neutron

# Restart neutron
service neutron-server restart

# Install Horizon
apt-get install -y openstack-dashboard apache2 libapache2-mod-wsgi memcached python-memcache

# Disable offline compression 
sed -i -e 's/COMPRESS_OFFLINE\ =\ True/COMPRESS_OFFLINE\ =\ False/' /etc/openstack-dashboard/local_settings.py

# Restart apache2 and memcached
service apache2 restart
service memcached restart

# Install Cinder
apt-get install -y cinder-api cinder-scheduler python-cinderclient

# Setup /etc/cinder/cinder.conf
cat > /etc/cinder/cinder.conf << EOF
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = tgtadm
volume_name_template = volume-%s
volume_group = cinder-volumes
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
control_exchange = cinder
notification_driver = messagingv2
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}
auth_strategy = keystone
my_ip = ${mgtip}

[database]
connection = mysql://cinderUser:${cinderdbpass}@${mgtip}/cinder

[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = cinder
admin_password = ${cinderuserpass}
EOF

# Populate database
su -s /bin/sh -c "cinder-manage db sync" cinder

# Restart Services
service cinder-scheduler restart
service cinder-api restart

# delete unneeded sqlite file
rm -f /var/lib/cinder/cinder.sqlite

# Install Orchestration
apt-get install -y heat-api heat-api-cfn heat-engine python-heatclient

# Edit /etc/heat/heat.conf
cat > /etc/heat/heat.conf << EOF
[DEFAULT]
log_dir=/var/log/heat
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}
heat_metadata_server_url = http://${mgtip}:8000
heat_waitcondition_server_url = http://${mgtip}:8000/v1/waitcondition

[auth_password]

[clients]

[clients_ceilometer]

[clients_cinder]

[clients_glance]

[clients_heat]

[clients_keystone]

[clients_neutron]

[clients_nova]

[clients_swift]

[clients_trove]

[database]
connection = mysql://heatUser:${heatdb}@${mgtip}/heat

[ec2authtoken]
auth_uri = http://controller:5000/v2.0

[heat_api]

[heat_api_cfn]

[heat_api_cloudwatch]


[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = heat
admin_password = ${heatuser}

[matchmaker_redis]

[matchmaker_ring]

[oslo_messaging_amqp]

[paste_deploy]

[revision]
EOF

# Populate heat database
su -s /bin/sh -c "heat-manage db_sync" heat

# Restart heat
service heat-api restart
service heat-api-cfn restart
service heat-engine restart

# Delete unneeded sqlite file
rm -f /var/lib/heat/heat.sqlite

# Install mongodb
apt-get install -y mongodb-server mongodb-clients python-pymongo

# Configure mongodb
sed -i "s/127.0.0.1/$mgtip/g" /etc/mongodb.conf
echo "smallfiles = true" >> /etc/mongodb.conf

# Delete journaldb files and restart mongodb
service mongodb stop
rm /var/lib/mongodb/journal/prealloc.*
service mongodb start

# Wait for mongodb to come back up
sleep 10

# Create ceilometer database
mongo --host ${mgtip} --eval '
db = db.getSiblingDB("ceilometer");
db.addUser({user: "ceilometer",
pwd: "'${ceilometerdb}'",
roles: [ "readWrite", "dbAdmin" ]})'

# Install ceilometer
apt-get install -y ceilometer-api ceilometer-collector ceilometer-agent-central \
ceilometer-agent-notification ceilometer-alarm-evaluator \
ceilometer-alarm-notifier python-ceilometerclient

# Create /etc/ceilometer/ceilometer.conf
cat > /etc/ceilometer/ceilometer.conf << EOF
[DEFAULT]
log_dir=/var/log/ceilometer
rpc_backend = rabbit
rabbit_userid = openstack
rabbit_host = ${mgtip}
rabbit_password = ${rabbitpw}
auth_strategy = keystone

[alarm]

[api]

[central]

[collector]

[compute]

[coordination]

[database]
connection = mongodb://ceilometer:${ceilometerdb}@${mgtip}:27017/ceilometer

[dispatcher_file]

[event]

[hardware]

[ipmi]

[keystone_authtoken]
auth_uri = http://${mgtip}:5000/v2.0
identity_uri = http://${mgtip}:35357
admin_tenant_name = service
admin_user = ceilometer
admin_password = ${ceilometeruser}

[matchmaker_redis]

[matchmaker_ring]

[notification]

[publisher]
metering_secret = ${ceilometersecret}

[publisher_notifier]

[publisher_rpc]

[service_credentials]
os_auth_url = http://${mgtip}:5000/v2.0
os_username = ceilometer
os_tenant_name = service
os_password = ${ceilometeruser}

[service_types]

[vmware]

[xenapi]
EOF

# Restart ceilometer
service ceilometer-agent-central restart
service ceilometer-agent-notification restart
service ceilometer-api restart
service ceilometer-collector restart
service ceilometer-alarm-evaluator restart
service ceilometer-alarm-notifier restart


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
    echo "Cinder MySQL Database Password: $cinderdbpass"
    echo "Glance MySQL Database Password: $glancedb"
    echo "Nova MySQL Database Password: $novadb"
    echo "Keystone MySQL Database Password: $keystonedb"
    echo "Neutron MySQL Database Password: $neutrondb"
    echo ""
    echo "Cinder Keystone User Password: $cinderuserpass"
    echo "Glance Keystone User Password: $glanceuser"
    echo "Nova Keystone User Password: $novauser"
    echo "Neutron Keystone User Password: $neutronuser"
    echo ""
    echo "RabbitMQ Pass: $rabbitpw"
    echo "Neutron Metadata Server's Shared Secret: $sharedsecret"
    echo "Ceilometer Server's Shared Secret: $ceilometersecret"
    echo ""

    echo ""
    echo "For installing the Cinder Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export cinderuserpass=$cinderuserpass"
    echo "export cinderdbpass=$cinderdbpass"
    echo "export rabbitpw=$rabbitpw"
    echo ""

    echo ""
    echo "For installing the Glance Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export glanceuserpass=$glanceuser"
    echo "export glancedbpass=$glancedb"
    echo "export rabbitpw=$rabbitpw"
    echo ""

    echo ""
    echo "For installing the Neutron Server you can export the following variables:"
    echo ""
    echo "export mgtip=$mgtip"
    echo "export neutronuserpass=$neutronuser"
    echo "export neutrondbpass=$neutrondb"
    echo "export ceilometersecret=$ceilometersecret"
    echo ""

    echo ""
    echo "For installing a Compute Server you can export the following variables:"
    echo ""
    echo "export controllerip=$mgtip"
    echo "export pubip=$pubip"
    echo "export glanceippass=$glanceip"
    echo "export neutronippass=$neutronip"
    echo "export neutronuserpass=$neutronuser"
    echo "export neutrondbpass=$neutrondb"
    echo "export novauserpass=$novauser"
    echo "export novadbpass=$novadb"
    echo "export sharedsecret=$sharedsecret"
    echo "export rabbitpw=$rabbitpw"
    echo "export keystonetoken=$keystonetoken"
    echo "export ceilometersecret=$ceilometersecret"
    echo ""

    echo ""
    echo "For using nova commands you need to source /root/.novarc first."

    echo ""
    echo "Run the following commands in order to fix nova's database"
    echo 'su -s /bin/sh -c "nova-manage db sync" nova'
    echo 'for service in nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler; do service $service restart; done'
fi
