#!/bin/bash

# Author: Nils Grundmann - 'ngrundmann'
# Version: 0.3.1

### Global Variables
##### define static variables

DATE=`date +%s`
DATE_HUMAN=`date +%F`

ELASTIC_NUMBER=0

### Global functions
##### set functions for date and directories

nl() {
echo ""
}

var_file_timestamp() {
FILE_TIMESTAMP=`grep -o "\"date\":\ \"[0-9]\{10\}\"" <<< $ELASTIC | cut -f 4 -d "\""`
}

var_filepath() {
FILEPATH="Results/$DATE_HUMAN/$LISTNAME/$PORT"
}

var_filename_range() {
FILENAME_RANGE="Ranges/$LISTNAME.txt"
}

### Check if Elastic and Kibana are running

check_es() {
systemctl status elasticsearch.service > /dev/null

if [ "$?" -gt "0" ]
then
	systemctl start elasticsearch.service

	nl

	echo "ElasticSearch wasn't running. I started it for you."

	echo ""
fi
}

check_kibana() {
systemctl status kibana.service > /dev/null

if [ "$?" -gt "0" ]
then
        systemctl start kibana.service

        nl

        echo "Kibana wasn't running. I started it for you."

        nl
fi
}

### Getting input
##### set functions for grabbing input from user

get_listname() {
read -p "Please provide a group name: " LISTNAME

var_filename_range
}

get_port() {
read -p "Please provide a port to scan (only one port or one port range seperated by '-'): " PORT

var_filepath
}

get_filename_ip() {
read -e -p "Please provide a file with IP addresses/ranges (each IP/range in a new line): " FILENAME_IP
}

get_json() {
read -e -p "Please provide a 'JSON' file output from masscan: " FILENAME_JSON
}

get_json_converted() {
read -e -p "Please provide a converted 'JSON' file: " FILENAME_JSON_CONVERTED
}

### Start
##### grab information from user

start() {
nl

if [ -n "$LISTNAME" ]
then
	echo "Group name is $LISTNAME"
fi

if [ -n "$PORT" ]
then
	echo "Checking on port $PORT"
fi

if [ -n "$FILENAME_IP" ]
then
	echo "Checking IP's from $FILENAME_IP"
fi

if [ -n "$FILENAME_OUTPUT" ]
then
	echo "Using JSON file $FILENAME_OUTPUT"
fi

sleep 2

if [ -n "$FILEPATH" ]
then
	nl

	echo "Doing stuff in $FILEPATH"
fi

sleep 3

nl

echo "If you want to abort, use 'CTRL+C' now!"

sleep 1

echo "3"
sleep 1

echo "2"
sleep 1

echo "1"
sleep 1

echo "Starting now..."

nl
}

### Create working directories

create_wd() {
if [ ! -d $FILEPATH ]
then
	mkdir -p $FILEPATH

	echo "INFO: Working directory created."
else
	echo "WARN: Working directory already exists, skipping!"
fi

if [ ! -d "Ranges" ]
then
	mkdir Ranges

	echo "INFO: 'Ranges' directory created."
else
	echo "WARN: 'Ranges' directory exists, skipping!"
fi

sleep 1
}

### Find ranges for IP's
##### grab, sort and filter ranges from input

find_ranges() {
for IP in $(cat $FILENAME_IP)
do
	whois -r $IP | grep inetnum | cut -f 9,10,11 -d " " | sed s/" "-" "/-/g >> $FILENAME_RANGE.tmp
done

sort -g $FILENAME_RANGE.tmp | uniq >> $FILENAME_RANGE

rm $FILENAME_RANGE.tmp

sleep 1
}

### Banner grabbing for ranges and save as JSON
##### run masscan with banner grabbing

banner_grabbing() {
for RANGE in $(cat $FILENAME_RANGE)
do
	masscan --ports $PORT $RANGE --banners --source-port 60000 -oJ $FILEPATH/$LISTNAME.$RANGE.json --rate 100000
done

FILENAME_JSON=`ls $FILEPATH/*.json`

sleep 1
}

### Convert JSON output for Elastic
##### convert JSON output from masscan to readable JSON output for Elastic

convert_json() {
for DOC in $FILENAME_OUTPUT
do
	sed -i 's/\ \ \ /\ /g' $DOC
	sed -i 's/\"ports\"\:\ \[\ {//' $DOC
	sed -i 's/\"service\"\:\ {//' $DOC
	sed -i 's/}\ ]/\,\ \"date\":\ \"'"$DATE"'\"/' $DOC
	sed -i 's/\"}\ ,\ \"/\",\ \"/' $DOC
	sed -i 's/,$//' $DOC
	sed -i '/^{[[:print:]]*\ [0-9]}/d' $DOC
done

FILENAME_OUTPUT_CONVERTED=$FILENAME_OUTPUT

sleep 1
}

### Import data to Elastic
##### create schema and import data to Elastic

import() {
curl -XPUT http://localhost:9200/masscan/_mapping/$LISTNAME?pretty -d '
{
  "properties": {
    "ip":         { "type": "ip" },
    "port":       { "type": "integer" },
    "proto":      { "type": "string" },
    "status":     { "type": "string" },
    "reason":     { "type": "string" },
    "ttl":        { "type": "string" },
    "banner":     { "type": "string" },
    "name":       { "type": "string" },
    "date":       { "type": "date", "format": "date||epoch_second" },
    "timestamp":  { "type": "date", "format": "date||epoch_second" }
  }
}'

for DOC in $FILENAME_OUTPUT_CONVERTED
do
	while read ELASTIC
	do
		var_file_timestamp

		curl -XPOST http://localhost:9200/masscan/$LISTNAME/${LISTNAME}_${FILE_TIMESTAMP}_${ELASTIC_NUMBER}?pretty -d "$ELASTIC"

		let "ELASTIC_NUMBER++"

	done < $DOC
done
}

### Help menu

help() {
echo "HELP MENU"
}

### Start options
##### call functions

start_options() {
case $OPTION in
	0*)
		check_es
		check_kibana

		sleep 1

		get_listname
		get_port
		get_filename_ip

		sleep 1

		start

		create_wd
		find_ranges
		banner_grabbing
		convert_json
		import
		;;
	1)
		get_listname
		get_filename_ip

		sleep 1

		start

		create_wd
		find_ranges
		;;
	2)
		get_listname
		get_filename_ip
		get_port

		sleep 1

		start

		create_wd
		banner_grabbing
		;;
	3)
		get_listname
		get_json

		sleep 1

		convert_json
		;;
	4)
		check_es
		check_kibana

		sleep 1

		get_listname
		get_json_converted

		sleep 1

		start

		import
		;;
	5)
		help
		;;
	*)
		echo "Nobody here"
		;;
esac
}

### Start
##### output for user

echo "Welcome!"

sleep 1

echo "[0] - All: searching IP ranges, banner grabbing, convert for Elastic, import in Elastic"
echo "[1] - Ranges: Only search for ranges for given IP's"
echo "[2] - Banner grabbing: Only do banner grabbing for given IP's/Ranges"
echo "[3] - Convert: Only convert existing data for Elastic"
echo "[4] - Import: Only import data to Elastic"
nl
echo "[5] - Help: Help menu"

nl
echo "#####"
nl

read -p "Please select one option: " OPTION

nl

start_options
