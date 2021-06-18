#!/bin/bash

# Use this Script to scale Servers hosted on hosttech.cloud automatically.

# This script requieres high privileges to make Changes on the System ressources. Run it as root.
if ! [ $(id -u) = 0 ]; then
	echo "This script should be used as root."
	exit 1
fi

if ! command -v jq >/dev/null; then
	read -p "This script requires jq to be installed to work. Would you like to install jq now? (Y/N)" answer
	if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
		apt update && apt install -y jq
	else
		echo "jq is reqiered. Exit now."
		exit 1
	fi
fi

conf=hosttechAutoscale.conf

if [[ -f $conf ]]; then
	source $conf
fi

#Initialize the Script and install a Cronjob, if desired.

function setavload() {
	case $avloadabc in
	a)
		avload=1
		avloadminutes=1
		;;
	b)
		avload=2
		avloadminutes=5
		;;
	c)
		avload=3
		avloadminutes=15
		;;
	esac
}

function initialize() {
	if [[ ! -f $conf ]]; then
		echo "This script scales your Server on the hosttech.cloud."
		read -p "Please enter your USER_UUID as found on https://hosttech.cloud/Easy/APIs/: " USER_UUID
		read -p "Please enter your API-Token as found on https://hosttech.cloud/Easy/APIs/: " API_TOKEN
		clear
		# Get the List of Servernames and SERVER_UUID
		serversjson=$(curl -s -H "Content-Type: application/json" \
			-H "X-Auth-UserId: $USER_UUID" \
			-H "X-Auth-Token: $API_TOKEN" \
			-X GET \
			https://api.hosttech.cloud/objects/servers)

		echo "These Servers are available:"
		echo $serversjson | jq '.[] | .[] | "\(.name) \(.object_uuid)" ' | tr -d "\"" | column -t -s' '

		read -p "Please enter the SERVER_UUID of this Server: " SERVER_UUID
		clear
		read -p "Enter max CPU (default 32): " cpumax
		if [[ -z "$cpumax" ]]; then
			cpumax=32
		else

			while [[ ! $cpumax =~ ^[0-9]+$ ]]; do
				read -p "Enter a valid number (default 32): " cpumax
				if [[ -z "$cpumax" ]]; then
					cpumax=32
				fi
			done

		fi

		[[ $cpumax =~ ^[0-9]+$ ]] && echo "Your host will scale up to $cpumax CPU cores"
		sleep 2
		clear
		echo -e "Depending on the Apps, Databases etc. it takes some time for the host to \"calm down\" afer reboot. \nBy default there is a delay of 10 Minutes until the script starts scaling. You can increase this value as you wish."
		read -p "Enter number of Minutes for delay: " delay

		if [[ -z "$delay" ]]; then
			delay=10
		else

			while [[ ! $delay =~ ^[0-9]+$ ]]; do
				read -p "Enter a valid number for the delay: " delay
				if [[ -z "$delay" ]]; then
					delay=10
				fi
			done

		fi

		[[ $delay =~ ^[0-9]+$ ]] && echo "You have set $delay minutes"
		sleep 2
		clear

		echo -e "Load is refered to as a Value counting all processes waiting to be executed on the next cycle. This script uses Load Average during one minute to decide if more ressources are needed. \nYou can choose either 1 Minute (a), 5 Minutes (b) or 15 Minutes (c)"
		echo "Enter a for 1 minute Average Load (default)"
		echo "Enter b for 5 minute Average Load"
		echo "Enter c for 15 minute Average Load"

		read avloadabc

		if [[ -z "$avloadabc" ]]; then
			avloadabc=a
			setavload

		else
			setavload
			while [[ ! $avloadabc =~ ^[a-c]+$ ]]; do
				read -p "Enter a valid value (a-c): " avloadabc

				setavload

				if [[ -z "$avloadabc" ]]; then
					avloadabc=a
					setavload
				fi
			done

		fi

		[[ $avloadabc =~ ^[a-c]+$ ]] && echo "You have set $avloadminutes minutes as Averave Load"

		sleep 2
		clear

		echo -e "Threshold is a value relative to all available cores. If you enter 50, the script already scales by one core when the CPU's capacity is half utilized."
		read -p "Enter Threshold (Number between 50-99, default: 90): " threshold

		if [[ -z "$threshold" ]]; then
			threshold=90
		else

			while [[ ! $threshold =~ ^[5-9][0-9]?$ ]]; do
				read -p "This Number is not valid. Enter Threshold (Number between 50-99, default: 90): " threshold
				if [[ -z "$threshold" ]]; then
					threshold=90
				fi
			done

		fi

		[[ $threshold =~ ^[5-9][0-9]?$ ]] && echo "You have set Threshold to $threshold% CPU utilization"

		touch hosttechAutoscale.conf
		cat <<EOT >>hosttechAutoscale.conf
USER_UUID="$USER_UUID"
API_TOKEN="$API_TOKEN"
SERVER_UUID="$SERVER_UUID"
cpumax="$cpumax"
delay="$delay"
avload="$avload"
threshold="$threshold"
EOT
		sleep 2
		clear
		echo "It's recommended to install a Cronjob for this script. Would you like to install a Cronjpb now?"
		read -p "Install Cronjob? (Y/N): " cronjob && [[ $cronjob == [yY] || $cronjob == [yY][eE][sS] ]] || exit 1
		if [[ $cronjob == [yY] || $cronjob == [yY][eE][sS] ]]; then
			echo cronjob
			crontab -l >mycron
			echo "* * * * * cd $PWD && /bin/bash $PWD/autoscale.sh >/dev/null 2>&1" >>mycron
			crontab mycron
			rm mycron
		fi
	fi
}

# Allocate new resources
function ressource_update() {
	# Based on script by William Lam - http://engineering.ucsb.edu/~duonglt/vmware/

	# Bring CPUs online
	for CPU_DIR in /sys/devices/system/cpu/cpu[0-9]*; do
		CPU=${CPU_DIR##*/}
		echo "Found cpu: '${CPU_DIR}' ..."
		CPU_STATE_FILE="${CPU_DIR}/online"
		if [ -f "${CPU_STATE_FILE}" ]; then
			if grep -qx 1 "${CPU_STATE_FILE}"; then
				echo -e "\t${CPU} already online"
			else
				echo -e "\t${CPU} is new cpu, onlining cpu ..."
				echo 1 >"${CPU_STATE_FILE}"
			fi
		else
			echo -e "\t${CPU} already configured prior to hot-add"
		fi
	done

	# Bring all new Memory online
	for RAM in $(grep line /sys/devices/system/memory/*/state); do
		echo "Found ram: ${RAM} ..."
		if [[ "${RAM}" == *":offline" ]]; then
			echo "Bringing online"
			echo $RAM | sed "s/:offline$//" | sed "s/^/echo online > /" | source /dev/stdin
		else
			echo "Already online"
		fi
	done
}

# Function to add more CPU and allocate them on the machine
function more_cpu() {
	cpu=${1:-1}
	cpuvar='{"cores": '$cpu' }'

	curl -H "Content-Type: application/json" \
		-H "X-Auth-UserId: $USER_UUID" \
		-H "X-Auth-Token: $API_TOKEN" \
		-d "$cpuvar" \
		-X PATCH \
		https://api.hosttech.cloud/objects/servers/$SERVER_UUID

	sleep 10
	ressource_update
}

initialize

# Variables for the Script. Finetuning should be made here.
cpu=$(grep -c ^processor /proc/cpuinfo)
cputotal=$((cpu))00
cpulimit=$(($cputotal / 100 * $threshold))
cpuuse=$(cat /proc/loadavg | awk '{print $'$avload'}' | tr -d "." | sed 's/^0*//')
uptime=$(uptime | awk '{print $3}' | cut -f 1 -d "," | tr -d ":")

echo "CPU Cores active: $cpu"
echo "Usage / Limit: $cpuuse/$cpulimit"

# This Script scales by 1 CPU if conditions are met (CPU-Threshold reached and Uptime longer than $delay Minutes).
if [[ $((cpuuse)) -ge $cpulimit && $((uptime)) -gt $delay ]]; then
	cpunew=$((cpu + 1))
	# Exit if maxcpu reached
	if [[ $cpunew > $cpumax ]]; then
		echo "Max CPU reached."
		exit
	fi
	echo "New CPU $cpunew"
	more_cpu $cpunew
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: The number of CPU on this Server was updated. $cpunew Cores are activ now." >>update.log
else
	exit
fi
