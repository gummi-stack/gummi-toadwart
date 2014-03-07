net = require 'net'
nm = require 'netmask'
exec = require('child_process').exec
Dhcp = require './dhcp.coffee'

config = process.config

net = new nm.Netmask config.lxc.address

basePort = 5000
rules = []
portMap = []
for i in [1...net.size - 2]
	basePort++
	nip = nm.long2ip(nm.ip2long(net.first) + i)
	portMap[nip] =
		publicIp: config.ip
		publicPort: basePort
		privatePort: basePort
		privateIp: nip
	rules.push "#{basePort}:#{nip}:#{basePort}"

rules = rules.join "\n"

ipenv =
	RULES: rules
	WAN_IFACE: config.wan.iface
	LXC_IFACE: config.lxc.iface
	LXC_IP: net.first
	LXC_MASK: net.mask

exports.init = (callback) ->
	exec "#{__dirname}/iptables.sh", env: ipenv, (err) ->
		return callback err if err

		dhcpConfig =
			addresses: nm.long2ip(nm.ip2long(net.first) + 1) + "-" + net.last
			mask: net.mask
			route: net.first
			portMap: portMap

		callback null, new Dhcp dhcpConfig
