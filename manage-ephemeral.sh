#!/bin/bash



LXC_BASE="child"
UNION="overlayfs"

action=$1


on_die()
{
    # print message
    #
    echo "Dying..."

    # Need to exit the script explicitly when done.
    # Otherwise the script would live on, until system
    # realy goes down, and KILL signals are send.
    #
    exit 0
}

#trap 'on_die' TERM

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
	#OVERLAY_DIR=`mktemp -d /tmp/lxc-lp-XXXXXXX`
	
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

    echo CFCFCFCFCFCF
    echo $LXC_IP
    echo $LXC_MASK
    echo $LXC_ROUTE
}

start_container()
{
    action=$1
    slug=$2
    src=$3
    worker=$3

   echo "Starting up the container..."

 #  ls -ls $LXC_DIR/rootfs/dev/

   rm $LXC_DIR/rootfs/dev/shm
   mkdir $LXC_DIR/rootfs/dev/shm


#   echo "route add default gw 172.16.226.2 " >> $LXC_DIR/rootfs/etc/rc.local

#echo
#mount
#echo

   APP_DIR=$LXC_DIR/rootfs/app
    mkdir -p $APP_DIR
#   echo "Copying application source"
#   cp -r /home/bender/testing/ $APP_DIR
#    CMD="/init $action $slug $worker"
#   sudo lxc-execute -n $LXC_NAME -- $CMD

    SLUG_NAME=$slug
    SLUG_FILE=/slugs/$SLUG_NAME.tar.gz


    if [ $action = "run" ]; then
	#TODO propasovat enviroment ? 
       tar -C $APP_DIR -xzf $SLUG_FILE
       CMD="/init $action $worker"
	   echo "SDSDSDSDSDSDSD"
       lxc-execute -n $LXC_NAME -- $CMD | rlogr -s lxc-exec -t


    fi

    if [ $action = "compile" ]; then
       echo "Copying application source"
	if [ ! -d $src ]; then
	   echo ">>>>>> Missing src dir"
	    exit 1
	fi
       #cp -r /home/bender/testing/* $APP_DIR
	#echo ">>>>>>>>>>$src"

	#exit 1
       cp -r $src/* $APP_DIR
       CMD="/init $action"
       lxc-execute -n $LXC_NAME -- $CMD | /root/toadwart/rlogr/rlogr -t -s nevim

        SLUG_NAME=$slug
	make_slug
    fi



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
# >&2
	LXC_NAME=$1
	setup_variables
	
	#exit 1
	sudo umount $EPHEMERAL_BIND_DIR
	sudo umount $LXC_DIR
	sudo umount $OVERLAY_DIR
	sudo rmdir $LXC_DIR
	sudo rmdir $OVERLAY_DIR
}


run_container()
{
	#CMD=$1
	
	#lxc-execute -n $LXC_NAME -- bash --verbose --init-file /root/.gummi -c $CMD # | rlogr -s lxc-exec -t
	# echo ---- $CMD
    # lxc-execute -n $LXC_NAME -- bash -c ". /root/.gummi; su -p user -c $CMD"

#    lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root; su user -c \". /init/user; ps afx\""
	
##	lxc-execute -s lxc.console=none -n child -- bash
	
	lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root $CMD " 

#| /root/toadwart/rlogr/rlogr -t -s netusim


    # lxc-execute -s lxc.console=none -n $LXC_NAME -- bash -c ". /root/.gummi; su -p user -c \"export XXX=10;$CMD\""

#    lxc-execute -n $LXC_NAME -- bash -c ". /root/.gummi; su -p user -c \"export XXX=10;$CMD\""



    # lxc-execute -n $LXC_NAME -- bash /root/.gummi
    # lxc-execute -n $LXC_NAME -- bash -c $CMD

}


if [ "$action" = "setup" ]; then
	setup_container
elif [ "$action" = "run" ]; then
	# echo "Poustim"
	# echo $@
	
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
	#echo "Koncim"
	#clean_container $LXC_NAME
	exit 1
	
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
