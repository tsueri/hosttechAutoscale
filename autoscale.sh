#!/bin/bash

# Use this Script to scale Servers hosted on hosttech.cloud automatically.

# This script requieres high privileges to make Changes on the System ressources. Run it as root.
if ! [ $(id -u) = 0 ]; then
	echo "This script should be used as root."
	exit 1
fi

if ! command -v jq >/dev/null; then
  read -p "This script requires jq to be installed and on your PATH. Would you like to install jq now? (Y/N)" answer
    if [[ "$answer" == "y" || "$answer" == "Y"  ]]; then
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
function initialize () {
	if [[ ! -f $conf ]]; then
		echo "This script scales your Server on the hosttech.cloud."
		read -p "Please enter your USER_UUID as found on https://hosttech.cloud/Easy/APIs/: " USER_UUID
		read -p "Please enter your API-Token as found on https://hosttech.cloud/Easy/APIs/: " API_TOKEN

		# Get the List of Servernames and SERVER_UUID
		serversjson=$(curl -H "Content-Type: application/json" \
		-H "X-Auth-UserId: $USER_UUID" \
		-H "X-Auth-Token: $API_TOKEN" \
		-X GET \
		https://api.hosttech.cloud/objects/servers)

		echo "These Servers are available:"
		echo $serversjson | jq '.[] | .[] | "\(.name) \(.object_uuid)" ' | tr -d "\"" | column -t -s' '

		read -p "Please enter the SERVER_UUID of this Server: " SERVER_UUID
    touch hosttechAutoscale.conf
cat <<EOT >> hosttechAutoscale.conf
USER_UUID="$USER_UUID"
API_TOKEN="$API_TOKEN"
SERVER_UUID="$SERVER_UUID"
EOT
		echo "It's recommended to install a Cronjob for this script. Would you like to install a Cronjpb now?"
		read -p "Install Cronjob? (Y/N): " cronjob && [[ $cronjob == [yY] || $cronjob == [yY][eE][sS] ]] || exit 1
		if [[ $cronjob == [yY] || $cronjob == [yY][eE][sS] ]]; then
			echo cronjob
			crontab -l > mycron
			echo "* * * * * cd $PWD && /bin/bash $PWD/autoscale.sh >/dev/null 2>&1" >> mycron
			crontab mycron
			rm mycron
		fi
	fi
}

# Allocate new Ressources
function ressource_update () {
	# Based on script by William Lam - http://engineering.ucsb.edu/~duonglt/vmware/

	# Bring CPUs online
	for CPU_DIR in /sys/devices/system/cpu/cpu[0-9]*
	do
    	CPU=${CPU_DIR##*/}
    	echo "Found cpu: '${CPU_DIR}' ..."
    	CPU_STATE_FILE="${CPU_DIR}/online"
    	if [ -f "${CPU_STATE_FILE}" ]; then
        	if grep -qx 1 "${CPU_STATE_FILE}"; then
            	echo -e "\t${CPU} already online"
        	else
            	echo -e "\t${CPU} is new cpu, onlining cpu ..."
            	echo 1 > "${CPU_STATE_FILE}"
        	fi
    else
        echo -e "\t${CPU} already configured prior to hot-add"
    fi
	done

	# Bring all new Memory online
	for RAM in $(grep line /sys/devices/system/memory/*/state)
	do
    	echo "Found ram: ${RAM} ..."
    	if [[ "${RAM}" == *":offline" ]]; then
        	echo "Bringing online"
        	echo $RAM | sed "s/:offline$//"|sed "s/^/echo online > /"|source /dev/stdin
    	else
        	echo "Already online"
    	fi
	done
}

# Function to add more CPU and allocate them on the machine
function more_cpu () {
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
cpulimit=$(( $cputotal / 100 * 90)) # Threshold: Change 90 to 80 if your Server should Scale up with 80 % Load.
cpuuse=$(cat /proc/loadavg | awk '{print $1}' | tr -d ".") # Change $1 to $2 if you want to use Load Calculations over 5 minutes. Switch to $3 if 15 Minutes should be used for calculations. This will impact the speed of scaling.
uptime=$(uptime | awk '{print $3}' | cut -f 1 -d "," | tr -d ":")

echo "CPU Cores active: $cpu"
echo "Usage / Limit: $cpuuse/$cpulimit"

# This script will not scale correctly for 1 CPU-Configurations. Below Load 1, the script exits and will not scale by the threshold.
if [[ $cpuuse = 0* ]]; then
	exit 1
fi

# This Script scales by 1 CPU if conditions are met (CPU-Threshold reached and Uptime longer than 10 Minutes).
if [[ $((cpuuse)) -ge $cpulimit && $((uptime)) -gt 10 ]]; then
	cpunew=$((cpu+1))
	echo "New CPU $cpunew"
	more_cpu $cpunew
	echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: The number of CPU on this Server was updated. $cpunew Cores are activ now." >> update.log
else
	exit
fi
