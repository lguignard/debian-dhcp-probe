#!/bin/sh
### BEGIN INIT INFO
# Provides:		dhcp-probe
# Required-Start:    	$local_fs $remote_fs $syslog $time $named $network
# Required-Stop:     	$local_fs $remote_fs $syslog $time $named $network 
# Default-Start:     	2 3 4 5
# Default-Stop:      	0 1 6
# Short-Description: 	dhcp-probe daemon to survey DHCP/BootP server on LAN
# Description: 		Enable or disable dhcp-probe service
### END INIT INFO

set -e

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON=/usr/sbin/dhcp_probe
LABEL=${DAEMON##*/}
NAME=dhcp-probe
PIDFILE=dhcp_probe.pid
BASE_RUNNING=/var/run
BASEPIDDIR=$BASE_RUNNING/$NAME
INITPIDFILE=$BASEPIDDIR/$PIDFILE
DESC="$NAME daemon"
ETC=/etc
LOGDIR=/var/log/$NAME.log
DODTIME=2   

test -x $DAEMON || exit 0

if [ -r /lib/lsb/init-functions ]; then 
	. /lib/lsb/init-functions
fi

sourceable() {
	[ -r $1 ] || return 1
  # Just to temporary files created by VIM
	case $1 in
		*\~)
			return 1
			;;
	esac
}

running() {
  INTERFACE=$1
  PIDFILE=$INITPIDFILE.$INTERFACE
	_max_repeat=10
	_repeat=1
	while [ ! -r $PIDFILE ] && [ $_repeat -le $_max_repeat ]; do
		printf "Waiting for pid file round: $_repeat\n" >&2
		sleep 1
		_repeat=$(($_repeat + 1))
	done
	printf "Waited ${_repeat}s to find a $INTERFACE pid file\n" >&2
  if [ $_repeat -le $_max_repeat ]; then
    read pid < $PIDFILE || return 1
  fi
  for i in `pidof dhcp_probe`; do
    if [ "$i" = "$pid" ]; then
      return 0
    fi
  done
  return 1
}

start_daemon() {
	# Start one daemon for each network interface
	[ -d $BASEPIDDIR ] || mkdir -p $BASEPIDDIR || {
		printf "Failed to create missing pid file directory $BASEPIDDIR!\n"
		return 1
	}
	sts=0
	for config_file in $ETC/$NAME/*; do
		sourceable $config_file || continue
		. $config_file
		PIDFILE=$INITPIDFILE.$INTERFACE
		DAEMON_OPTS="-T -p $PIDFILE $INTERFACE"
		printf "Starting $DESC on interface $INTERFACE: "
		max_repeat=10
		repeat=1
		while ip=$(sleep 1
			printf "\nstart_daemon - Waiting for an ip on iface $INTERFACE, round: \
      $repeat" >&2
      /sbin/ifconfig $INTERFACE | grep inet\  | awk '{ print $2 }' | \
      awk -F: '{ print $2 }'
			) && [ -z "$ip" ] && [ $repeat -le $max_repeat ]; do
			repeat=$(($repeat + 1))
		done
		printf "\nwaited ${repeat}s to get an ip on $INTERFACE" >&2

		start-stop-daemon --start --quiet --pidfile $PIDFILE \
			--exec $DAEMON -- $DAEMON_OPTS
		if running $INTERFACE; then
			printf "Done.\n"
		else
			printf "Failed!\n"
			sts=1
		fi
	done
	return $sts
}

stop_daemon() {
# Stop all existing dhcp_probe daemon
	for config_file in $ETC/$NAME/*; do
		sourceable $config_file || continue
		. $config_file
		PIDFILE=$INITPIDFILE.$INTERFACE
		if [ -r $PIDFILE ]; then
			printf "Stopping $DESC on interface $INTERFACE: "
			start-stop-daemon --stop --quiet --pidfile $PIDFILE 
			printf "$NAME.\n"
			rm -f $PIDFILE
    else
      force_stop
		fi
	done
}

force_stop() {
	# Forcefully kill the process
	for config_file in $ETC/$NAME/*; do
		sourceable $config_file || continue
		. $config_file
		PIDFILE=$INITPIDFILE.$INTERFACE
		if [ -r "$PIDFILE" ]; then
      if running $INTERFACE; then
        start-stop-daemon -K 15 --quiet --pidfile $PIDFILE \
          --exec $DAEMON -- $DAEMON_OPTS
              # Is it really dead?
        [ -z "$DODTIME" ] || sleep "$DODTIME"
        if running $INTERFACE; then
          start-stop-daemon -K 9 --quiet --pidfile $PIDFILE \
            --exec $DAEMON -- $DAEMON_OPTS
          [ "$DODTIME" ] || sleep "$DODTIME"
          if running $INTERFACE; then
            printf "Cannot kill $LABEL (pid=$pid)!\n"
            exit 1
          fi
        fi
      fi
    else
      killall `basename $DAEMON`
    fi
		rm -f $PIDFILE
	done
}


case $1 in
	start)
		start_daemon
		;;

	stop)
		stop_daemon
		;;

	force-stop)
		for config_file in $ETC/$NAME/*; do
			sourceable $config_file || continue
			. $config_file
			PIDFILE=$INITPIDFILE.$INTERFACE
			printf "Forcefully stopping $DESC: "
			force_stop
			if ! running $INTERFACE; then
				printf "$NAME on interface $INTERFACE.\n"
			else
				printf "Error !\n"
			fi
		done
		;;

	force-reload)	# Need to be improved
		printf "Reload operation is not supported -- use restart.\n"
		exit 1
		;;

	restart)
		printf "Restarting $DESC: "
		stop_daemon
		[ -z "$DODTIME" ] || sleep $DODTIME
		start_daemon
		printf "$NAME."
		;;

	status)
		for config_file in $ETC/$NAME/*; do
			sourceable $config_file || continue
			. $config_file
			PIDFILE=$INITPIDFILE.$INTERFACE
			printf "$LABEL is "
			if running $INTERFACE;  then
				printf "running on interface $INTERFACE.\n"
			else
				printf "not running.\n"
				exit 1
			fi
		done
		;;

	*)
		N=/etc/init.d/$NAME
		printf "Usage: $N {start|stop|restart|status|force-stop}\n" >&2
		exit 1
		;;
esac

exit 0
