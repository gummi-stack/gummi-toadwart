gummi-toadwart
==============




lxc-start -n master
ifconfig eth0 172.16.1.66 netmask 255.255.255.0
route add default gw 172.16.1.1
