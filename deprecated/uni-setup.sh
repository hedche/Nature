#!/bin/bash

# Author: Monty Rhodes
# Created: 23/12/2021
# This universal setup script will ask for a hostname, then run the corresponding setup.sh script 

echo "Running universal setup ..."

read -r "Please specify the hostname of this server:" hostname

if [ $hostname == "habitat" ]; then

	sudo habitat/setup/setup.sh

elif [ $hostname == "cloudmon" ]; then

	sudo ./cloudmon/setup/setup.sh

fi

