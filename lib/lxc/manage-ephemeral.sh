#!/bin/bash
set -e

# env


mkdir -p /var/lib/lxc

LXC_BASE_PATH="/srv/gummi/stacks"
LXC_BASE="gummiglen"
UNION="overlayfs"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$DYNO_UUID" = "" ]; then
    DYNO_UUID=unknown-manage
fi


if [ -z "$DYNO_UUID" ]; then
	echo Missing DYNO_UUID
	exit 1
fi

on_die()
{
	echo "Stopped container $LXC_NAME for $LOG_APP" #| $DIR/pr -u $DYNO_UUID > $RLOGR   #$RLOGR  -s $LOG_CHANNEL -a dyno

    # Need to exit the script explicitly when done.
    # Otherwise the script would live on, until system
    # realy goes down, and KILL signals are send.
    #
    exit 0
}

trap 'on_die' TERM

setup_variables()
{
	OVERLAY_DIR="/tmp/lxc-$LXC_NAME"
	LXC_DIR="/var/lib/lxc/$LXC_NAME"
	EPHEMERAL_BIND_DIR=$LXC_DIR/ephemeralbind

}


setup_container()
{
	# echo "Setting up ephemeral container"
	LXC_DIR=`sudo mkdir -p /var/lib/lxc/$LXC_NAME`
	# LXC_NAME=`basename $LXC_DIR`

	# LXC_DIR=`sudo mktemp -d --tmpdir=/var/lib/lxc $LXC_BASE-temp-XXXXXXX`
	# LXC_NAME=`basename $LXC_DIR`

	setup_variables


	mkdir $OVERLAY_DIR

	sudo mount -t tmpfs none $OVERLAY_DIR
	do_mount "$LXC_BASE_PATH/$LXC_BASE" "${OVERLAY_DIR}" $LXC_DIR
	sudo mkdir $EPHEMERAL_BIND_DIR
	sudo mount -t tmpfs none $EPHEMERAL_BIND_DIR

	# Update the ephemeral lxc's configuration to reflect the new container name.
	sudo sed -i -e "s/$LXC_BASE/$LXC_NAME/" $LXC_DIR/fstab $LXC_DIR/config $LXC_DIR/rootfs/etc/hostname $LXC_DIR/rootfs/etc/hosts

	# Update the fstab to have all bind mounts be ephemeral.
	#sudo cp $LXC_DIR/fstab $LXC_DIR/fstab.old
	#cat $LXC_DIR/fstab
	update_config

	# echo $LXC_NAME
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
	elif [ "${line:0:21}" = "lxc.network.veth.pair" ]; then
		echo "lxc.network.veth.pair = $LXC_NAME" #| sed "s/child-temp-//"
	elif [ "${line:0:10}" = "lxc.rootfs" ]; then
		echo "lxc.rootfs = $LXC_DIR/rootfs"
	elif [ "${line:0:9}" = "lxc.mount" ]; then
		echo "lxc.mount = $LXC_DIR/fstab"
	else
		echo "$line"
	fi
    done
    ) < ${c}.old | sudo tee ${c} >/dev/null
    sudo rm -f ${c}.old
    # cfg=$LXC_DIR/rootfs/init/env

    # echo LXC_IP=$LXC_IP >> $cfg
    # echo LXC_MASK=$LXC_MASK >> $cfg
    # echo LXC_ROUTE=$LXC_ROUTE >> $cfg

	# cat $c
	## TODO zvazit i jine varianty
	cp /etc/resolv.conf $LXC_DIR/rootfs/etc/resolv.conf
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

	echo "Stopping lxc $LXC_NAME"
	LXC_NAME=$1
	setup_variables

	lxc-stop -n $LXC_NAME  # aby se zabranilo hnilobe
	sudo umount $EPHEMERAL_BIND_DIR
	sudo umount $LXC_DIR
	sudo umount $OVERLAY_DIR
	sudo rmdir $LXC_DIR
	sudo rmdir $OVERLAY_DIR
}

# LOG_APP=`echo hera/mertrics-api | tr '/' '\/'`


# log2() {
# 	echo $@ | sed -e "s/^/`echo gummi $REPO` build 1 /"  | logger -t GUMMI
#
# }

log () {
	# echo $@ | sed -e "s/^/`echo gummi $REPO` build 1 /"  | logger -t GUMMI

	# TODO
	# gummi build
	# gummi web.1


	gummi-prefixer GUMMI "$LOG_SOURCE $LOG_APP $LOG_BRANCH $LOG_WORKER" echo $@ > /dev/null


	# echo $@ | sed -e "s/^/dyno $LOG_APP web.1 0 /"  | logger -t GUMMI
	# echo $@ | sed -e "s/^/dyno $LOG_APP web.1 0 /"  | logger -t GUMMI
	# echo $@
}

run_container()
{
	# env
	# echo '////////////////////////////////////////>>>>>>>>>>>'
	# echo $CMD
	# echo asdasda asd | logger -t GUMMI
	# echo gummi-prefixer GUMMI gummi $REPO dyno.1 echo "Starting container $LXC_NAME for $LOG_APP: $LOG_CMD"
	# mertrics-api |  dyno |  web.1  | 0 |
	log "Starting container $LXC_NAME -- $CMD"
	# echo "Starting container $LXC_NAME for $REPO: $CMD" | sed -e "s/^/`echo gummi $REPO` build 1 /"  | logger -t GUMMI

	# gummi-prefixer GUMMI $REPO dyno.1 ls -la
	# gummi-prefixer GUMMI $REPO dyno.1
	# echo "Starting container $LXC_NAME for $LOG_APP: $LOG_CMD" | sed -e "s/^/`echo $(REPO)` dyno\.1 1 /" | logger -t GUMMI

	# #####| $DIR/pr -u $DYNO_UUID > $RLOGR

	# TODO presmerovavat  2>&1 kdyz neni rendezvous
	# env
	# echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>" $CMD
	if [ "$LXC_RENDEZVOUS" = 1 ]; then
		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root $CMD " # | $RLOGR -t -s $LOG_CHANNEL -a
		# echo "----> " lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD

		# echo "exec RV------"

		# echo lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD
		lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD

		# echo "dasdsaiodjiodjiwodjiqwdjoweq@@@@@@@@"
		# sleep 10000
		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD # /init/root release
		# gummi-prefixer GUMMI "nevim $LOG_APP run.1" lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD




		# echo $CMD
	    # # | $RLOGR -t -s $LOG_CHANNEL -a
	else
#		lxc-execute -s lxc.console=none -n $LXC_NAME  -- bash -c ". /init/root $CMD " 2>&1 | $DIR/pr -u $LOG_UUID > $RLOGR
		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD ####2>&1 | $DIR/pr -u $LOG_UUID > $RLOGR

		# env
		# funguje ale zvraci sracky
		# echo gummi-prefixer GUMMI "app $LOG_APP web.1" lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD
# 		gummi-prefixer GUMMI "app $LOG_APP web.1" lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD
#
# 		echo xxxxxx
#
# 		sleep 10000000
# 		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD
		# echo "start	"
			gummi-prefixer GUMMI "app $LOG_APP $LOG_BRANCH $LOG_WORKER" lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD

			#2>&1

		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD  2>&1 | sed  -u -e "s/^/`echo $LOG_SOURCE $LOG_APP $LOG_BRANCH $LOG_WORKER` buildXX 1 /" | logger -t GUMMI
		# echo	 "bum"







		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD 2>&1 | sed -e "s/^/0.0.0.0 `echo  gummi $REPO` build 1 /"  | logger -t GUMMI


		# 2>&1 | sed -e "s/^/`echo gummi $REPO` build 1 xxxx/"  | logger -t GUMMI

		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD 2>&1 | sed -e "s/^/`echo gummi $REPO` build 1 xxxx/"  | logger -t GUMMI

		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- $CMD 2>&1 | sed -e "s/^/`echo gummi $REPO` build 1 /"  | logger -t GUMMI

		# lxc-execute -s lxc.console=none -n $LXC_NAME  -- env ####2>&1 | $DIR/pr -u $LOG_UUID > $RLOGR
	fi
	EXITCODE=$?
	# echo "Stopped container $LXC_NAME for $LOG_APP" | sed -e "s/^/`echo $(REPO)` dyno\.1 1 /" | logger -t GUMMI
	log "Stopped container $LXC_NAME"

}


action=$1

if [ "$action" = "setup" ]; then
	LXC_NAME=$2
	setup_container
	exit 0

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
	exit $EXITCODE

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
