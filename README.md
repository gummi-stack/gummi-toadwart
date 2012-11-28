gummi-toadwart
==============


npm install coffee-script -g


npm install http://github.com/gummi-stack/gummi-toadwart/tarball/master -g

toadwart config name stoupa-lukas-vbox
toadwart config port 80
toadwart config ip 10.11.1.9
toadwart config dhcp.addresses '192.168.73.2-192.168.73.254'
toadwart config dhcp.mask 255.255.255.0
toadwart config dhcp.route 192.168.73.2


bin/toadwart config name stoupa-nag
bin/toadwart config port 81
bin/toadwart config ip 10.1.69.105
bin/toadwart config dhcp.addresses '10.1.69.50-10.1.69.100'
bin/toadwart config dhcp.mask 255.255.255.0
bin/toadwart config dhcp.route 10.1.69.105
