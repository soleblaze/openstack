# Multi-Node 2 NIC Setup

This example has the following hardware:

1 Machine running the Controller, Cinder, Glance, and Quantum node
1 Machine running the Compute node

## Installing Controller/Cinder/Glance/Quantum Node

Install Ubuntu 12.04 LTS

ssh into controller

  screen

Add management interface to /etc/network/interfaces

auto eth1  
iface eth1 inet static  
  address 172.16.0.2  
  netmask 255.255.255.0  

	service networking restart

	wget https://github.com/soleblaze/openstack/raw/master/controller.sh
	
	chmod +x controller.sh
	
	./controller.sh | tee output.controller
	
	Input Management Interface: eth1
	Input Public Interface: eth0
	Input Admin Password: password
	Input MySQL Root Password: password
	Input Cinder IP [172.16.0.2]:
	Input Glance IP [172.16.0.2]:
	Input EC2 IP [172.16.0.2]:
	Input Quantum IP [172.16.0.2]:
	Reading package lists...
	Building dependency tree...

copy and paste the huge export list

	wget https://github.com/soleblaze/openstack/raw/master/glance.sh

	chmod +x glance.sh
	
	./glance.sh | tee output.glance
	
	Input Data Interface: eth1
	Input Controller IP [172.16.0.2]:
	Reading package lists...

	wget https://github.com/soleblaze/openstack/raw/master/cinder.sh
	
	chmod +x cinder.sh

	./cinder.sh | tee output.cinder
	
	Input Data Interface: eth1
	Input Controller IP [172.16.0.2]:
	Reading package lists...
	
	wget https://github.com/soleblaze/openstack/raw/master/quantum.sh
	
	chmod +x quantum.sh
	
	./quantum.sh | tee output.quantum; shutdown -r now


	Input Quantum Network Interface: eth1
	Input Public Interface: eth0
	Input Controller IP [172.16.0.2]:
	Reading package lists...
