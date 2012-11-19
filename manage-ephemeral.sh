#!/bin/bash

LXC_BASE="child"
UNION="overlayfs"
RLOGR=/root/toadwart/rlogr/rlogr



on_die()
{
	echo "Stopped container for $LOG_APP" | $RLOGR  -s $LOG_CHANNEL -a dyno

    # Need to exit the script explicitly when done.
    # Otherwise the script would live on, until system
    # realy goes down, and KILL signals are send.
    #
    exit 0
}

trap 'on_die' TERM

setup_variables()
{
	OVERLAY_DIR="/tmp/$LXC_NAME"
	LXC_DIR="/var/lib/lxc/$LXC_NAME"
	EPHEMERAL_BIND_DIR=$LXC_DIR/ephemeralbind
	
}


setup_container()
{
	# echo "Setting up ephemeral container"

	LXC_DIR=`sudo mktemp -d --tmpdir=/var/lib/lxc $LXC_BASE-temp-XXXXXXX`
	LXC_NAME=`basename $LXC_DIR`
	
	setup_variables
	
	
	mkdir $OVERLAY_DIR
	
	sudo mount -t tmpfs none $OVERLAY_DIR
	do_mount "/var/lib/lxc/$LXC_BASE" "${OVERLAY_DIR}" $LXC_DIR
	sudo mkdir $EPHEMERAL_BIND_DIR
	sudo mount -t tmpfs none $EPHEMERAL_BIND_DIR

	# Update the ephemeral lxc's configuration to reflect the new container name.
	sudo sed -i -e "s/$LXC_BASE/$LXC_NAME/" $LXC_DIR/fstab $LXC_DIR/config $LXC_DIR/rootfs/etc/hostname $LXC_DIR/rootfs/etc/hosts

	# Update the fstab to have all bind mounts be ephemeral.
	#sudo cp $LXC_DIR/fstab $LXC_DIR/fstab.old
	#cat $LXC_DIR/fstab
	update_config
	
	echo $LXC_NAME
}

update_config() {

    c=$LXC_DIR/config
    # change hwaddrs
    sudo mv ${c} ${c}.old
    #ip = "172.16.226"$[($RANDOM % 100 + 100)]
    (
    while read line; do
	if [ "${line:0:18}" = "lxc.network.hwaddr" ]; then
	    echo "lxc.network.hwaddr= 00:16:3e:$(openssl rand -hex 3| sed 's/\(..\)/\1:/g; s/.$//')"
	else
	    echo "$line"
	fi
    done
    ) < ${c}.old | sudo tee ${c} >/dev/null
    sudo rm -f ${c}.old
    cfg=$LXC_DIR/rootfs/init/env
    echo LXC_IP=$LXC_IP >> $cfg
    echo LXC_MASK=$LXC_MASK >> $cfg
    echo LXC_ROUTE=$LXC_ROUTE >> $cfg
}

do_mount() {
   lower=$1
   upper=$2
   target=$3
   if [ $UNION = "aufs" ]; then
       sudo mount -t aufs -o br=${upper}=rw:${lower}=ro,noplink none ${target}
   else
       sudo mount -t overlayfs -oupperdir=${upper},lowerdir=${lower} none ${target}
   fi
}

clean_container()
{
	
	echo "Stopping lxc" 
	LXC_NAME=$1
	setup_variables

	lxc-stop -n $LXC_NAME  # aby se zabranilo hnilobe
	sudo umount $EPHEMERAL_BIND_DIR
	sudo umount $LXC_DIR
	sudo umount $OVERLAY_DIR
	sudo rmdir $LXC_DIR
	sudo rmdir $OVERLAY_DIR
}


run_container()
{
	echo "Starting container for $LOG_APP $LOG_CMD" | $RLOGR  -s $LOG_CHANNEL -a dyno
	
	
	# TODO presmerovavat  2>&1 kdyz neni rendezvous
	
	
	if [ "$LXC_RENDEZVOUS" = 1 ]; then
		lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root $CMD " # | $RLOGR -t -s $LOG_CHANNEL -a 
	else
		lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root $CMD " 2>&1 | $RLOGR -t -s $LOG_CHANNEL -a $LOG_APP		
	fi
	echo "Stopped container for $LOG_APP" | $RLOGR  -s $LOG_CHANNEL -a dyno
	
}


action=$1

if [ "$action" = "setup" ]; then
	setup_container
elif [ "$action" = "run" ]; then

	LXC_NAME=$2
	CMD=$3
	shift
	shift
	shift
	CMD=$@

	if [ "$CMD" = "" ]; then
		echo "Missing command!"
		clean_container $LXC_NAME
		exit 1
	fi
	run_container
	exit $?
	
elif [ "$action" = "clean" ]; then
	clean_container $2

elif [ "$action" = "cleanall" ]; then
	# exclude running and frozen
	CONTAINERS=$(lxc-list | tr -d "\n" | sed "s/.*STOPPED //g")
	for container in $CONTAINERS; do
		if [[ $container =~ child-temp.* ]]; then
			clean_container $container
			echo $container removed
		fi
	done
else
	echo "usage: $0 [setup|run|clean|cleanall] <name> -- <command>"
	echo ""
fi

exit 0
