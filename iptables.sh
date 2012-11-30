#!/bin/sh
IPT="iptables -t nat "
CHAIN=TOADWART


ifconfig $LXC_IFACE $LXC_IP netmask $LXC_MASK


$IPT -D POSTROUTING -o $WAN_IFACE -j MASQUERADE 2> /dev/null
$IPT -A POSTROUTING -o $WAN_IFACE -j MASQUERADE

$IPT -D PREROUTING -j $CHAIN 2> /dev/null
$IPT -F $CHAIN 2> /dev/null	
$IPT -X $CHAIN 2> /dev/null	
$IPT -N $CHAIN 	
$IPT -A PREROUTING -j $CHAIN 	

for RULE in $RULES; do
	FROM_PORT=`echo $RULE | awk -F: '{print $1}'`
	TO_IP=`echo $RULE | awk -F: '{print $2}'`
	TO_PORT=`echo $RULE | awk -F: '{print $3}'`
	
	$IPT -A $CHAIN -t nat -i $WAN_IFACE -p tcp --dport $FROM_PORT -j DNAT --to $TO_IP:$TO_PORT
done
