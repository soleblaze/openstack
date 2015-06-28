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

if [ -z "$neutronvlan" ]; then
    echo -n "Enter VLAN range if using (otherwise press enter): "
    read neutronvlan
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

# Add repos for kilo if they don't already exist
if [ ! -e /etc/apt/sources.list.d/cloudarchive-kilo.list ]; then
    apt-get install -y ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu trusty-updates/kilo main >> /etc/apt/sources.list.d/cloudarchive-kilo.list
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

# Disable keystone service from starting after installation
echo "manual" > /etc/init/keystone.override

# Install keystone
apt-get install keystone python-openstackclient apache2 libapache2-mod-wsgi memcached python-memcache

# TODO: Update this to use memcache (memcache, token, revoke)
# Setup keystone.conf
sed -i -e "s|^#admin_token.*|admin_token=${keystonetoken}|" /etc/keystone/keystone.conf
sed -i -e "s|^#provider.*|provider = keystone.token.providers.uuid.Provider|" /etc/keystone/keystone.conf
sed -i -e "s|^#driver=keystone.token.persistence.backends.sql.Token|driver = keystone.token.persistence.backends.sql.Token|" /etc/keystone/keystone.conf
sed -i -e "s|^#driver=keystone.contrib.revoke.backends.kvs.Revoke|driver = keystone.contrib.revoke.backends.sql.Revoke|" /etc/keystone/keystone.conf
sed -i -e "s|^connection.*|connection\ =\ mysql://keystoneUser:${keystonedb}@${mgtip}/keystone|" /etc/keystone/keystone.conf


# Sync and restart the keystone service
su -s /bin/sh -c "keystone-manage db_sync" keystone

#TODO: Setup apache2 for keystone
sed -i -e 's/ServerName.*/ServerName\ controller/'  /etc/apache2/apache2.conf
cat > /etc/apache2/sites-available/wsgi-keystone.conf << EOF
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /var/www/cgi-bin/keystone/main
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    LogLevel info
    ErrorLog /var/log/apache2/keystone-error.log
    CustomLog /var/log/apache2/keystone-access.log combined
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /var/www/cgi-bin/keystone/admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    LogLevel info
    ErrorLog /var/log/apache2/keystone-error.log
    CustomLog /var/log/apache2/keystone-access.log combined
</VirtualHost>
EOF

# Enable Identity service virtual hosts
ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled

# Setup WSGI componetns
mkdir -p /var/www/cgi-bin/keystone
curl http://git.openstack.org/cgit/openstack/keystone/plain/httpd/keystone.py?h=stable/kilo \
| tee /var/www/cgi-bin/keystone/main /var/www/cgi-bin/keystone/admin

# Fix ownership of keystone directory
chown -R keystone:keystone /var/www/cgi-bin/keystone
chmod 755 /var/www/cgi-bin/keystone/*

# Restart Apache
service apache2 restart

# Delete uneeded sqlite file
rm -f /var/lib/keystone/keystone.db

# Setup cron to purge tokens hourly
(crontab -l -u keystone 2>&1 | grep -q token_flush) || \
echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' \
>> /var/spool/cron/crontabs/keystone

# Setup Keystone

## Set Variables for keystone
export OS_SERVICE_TOKEN=${keystonetoken}
export OS_SERVICE_ENDPOINT=http://${mgtip}:35357/v2.0

## Pause for 5 seconds so keystone has a chance to completely start
sleep 5

if [ -z "$KEYSTONE_REGION" ]; then
    export KEYSTONE_REGION=RegionOne
fi

# Setup Token
export OS_TOKEN=${keystonetoken}
export OS_URL=http://${mgtip}:35357/v2.0

# Create identity service
openstack service create --name keystone --description "OpenStack Identity" identity
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':5000/v2.0' --adminurl 'http://'"$mgtip"':35357/v2.0' --internalurl 'http://'"$mgtip"':5000/v2.0' identity

# Create default admin projects and roles
openstack project create --description "Admin Project" admin
openstack user create --password "$ADMIN_PASSWORD"  admin
openstack role create admin
openstack role add --project admin --user admin admin
openstack project create --description "Service Project" service
openstack role create user

# Glance User
openstack user create --password "$glanceuser" glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$glanceip"':9292' --adminurl 'http://'"$glanceip"':9292' --internalurl 'http://'"$glanceip"':9292' image

# Nova User
openstack user create --password "$novauser" nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s' --adminurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s' --internalurl 'http://'"$mgtip"':8774/v2/%(tenant_id)s' compute

# Neutron User
openstack user create --password "$neutronuser" neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':9696/' --adminurl 'http://'"$mgtip"':9696/' --internalurl 'http://'"$mgtip"':9696/' network

# Cinder User
openstack user create --password "$cinderuserpass" cinder
openstack role add --project service --user cinder admin
openstack service create --name cinder --description "OpenStack Block Storage" volume
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --adminurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --internalurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' volume
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --adminurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' --internalurl 'http://'"$cinderip"':8776/v2/%(tenant_id)s' volume2

# Glance User
openstack user create --password "$heatuser" heat
openstack role add --project service --user heat admin
openstack role create heat_stack_owner
openstack role create heat_stack_user
openstack service create --name heat --description "Orchestration" orchestration
openstack service create --name heat-cfn --description "Orchestration"  cloudformation
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':8004/v1/%(tenant_id)s' --adminurl 'http://'"$mgtip"':8004/v1/%(tenant_id)s' --internalurl 'http://'"$mgtip"':8004/v1/%(tenant_id)s' orchestration
openstack endpoint create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':8000/v1' --adminurl 'http://'"$mgtip"'8000/v1' --internalurl 'http://'"$mgtip"':800/v1' cloudformation

# Telemetry User
openstack user create --password "$ceilometeruser" ceilometer
openstack role add --project service --user ceilometer admin
openstack service create --name ceilometer --description "Telemetry" metering
openstack service create --region $KEYSTONE_REGION --publicurl 'http://'"$mgtip"':8777' --adminurl 'http://'"$mgtip"':8777' --internalurl 'http://'"$mgtip"':8777' metering

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
rpc_backend = rabbit
rabbit_host = $mgtip
rabbit_userid = openstack
rabbit_password = $rabbitpw
auth_strategy = keystone
my_ip = $mgtip
vncserver_listen = $mgtip
vncserver_proxyclient_address = $mgtip
network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver

[database]
connection = mysql://novaUser:$novadb@$mgtip/nova

[keystone_authtoken]
auth_uri = http://$mgtip:5000/v2.0
identity_uri = http://$mgtip:35357
admin_tenant_name = service
admin_user = nova
admin_password = $novauser

[glance]
host = $glanceip

[neutron]
url = http://${mgtip}:9696
auth_strategy = keystone
admin_auth_url = http://${mgtip}:35357/v2.0
admin_tenant_name = service
admin_username = neutron
admin_password = ${neutronuser}
service_metadata_proxy = True
metadata_proxy_shared_secret = ${sharedsecret}
EOF

# Sync nova database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
--config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

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

[nova]
auth_url = http://${mgtip}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = ${KEYSTONE_REGION}
project_name = service
username = nova
password = ${novauser}

[matchmaker_redis]

[matchmaker_ring]

[quotas]

[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

[keystone_authtoken]
auth_uri = http://${mgtip}:5000
auth_url = http://${mgtip}:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $neutronuser

[database]
connection = mysql://neutronUser:${neutrondb}@${mgtip}/neutron

[service_providers]
service_provider=LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
service_provider=VPN:openswan:neutron.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default
EOF

## Setup /etc/neutron/plugins/ml2/ml2_conf.ini
cat > /etc/neutron/plugins/ml2/ml2_conf.ini << EOF
[ml2]
type_drivers = flat,gre,vlan,vxlan
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

if [ "$neutronvlan" ]; then
    sed -i -e "s|\[ml2_type_vlan\]|[ml2_type_vlan]\nnetwork_vlan_ranges = external:$neutronvlan|" /etc/neutron/plugins/ml2/ml2_conf.ini
fi 


# Populate database
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
--config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade juno" neutron

# Restart neutron
service neutron-server restart

# Install Horizon
apt-get install openstack-dashboard

# Update local_settings.py
# TODO:
#OPENSTACK_HOST = "controller"
# ALLOWED_HOSTS = '*'
# CACHES = {
#   'default': {
#       'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
#       'LOCATION': '127.0.0.1:11211',
#   }
#}
# OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"
# TIME_ZONE = "TIME_ZONE"

# Restart apache2 and memcached
service apache2 reload

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
auth_strategy = keystone
my_ip = ${mgtip}

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
    echo "export sharedsecret=$sharedsecret"
    echo "export rabbitpw=$rabbitpw"
    echo ""

    echo ""
    echo "For installing a Compute Server you can export the following variables:"
    echo ""
    echo "export controllerip=$mgtip"
    echo "export pubip=$pubip"
    echo "export glanceip=$glanceip"
    echo "export neutronuserpass=$neutronuser"
    echo "export neutrondbpass=$neutrondb"
    echo "export novauserpass=$novauser"
    echo "export novadbpass=$novadb"
    echo "export sharedsecret=$sharedsecret"
    echo "export rabbitpw=$rabbitpw"
    echo "export keystonetoken=$keystonetoken"
    echo "export ceilometersecret=$ceilometersecret"
    echo "export ceilometeruserpass=$ceilometeruser"
    echo ""

    echo ""
    echo "For using nova commands you need to source /root/.novarc first."
fi
