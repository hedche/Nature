#!/bin/bash

# Author: Monty Rhodes
# Created: 23/12/2021
# This setup script will

echo "Running setup ..."

read -r "Please specify the hostname of this server" hostname

if [ $hostname == "habitat" ]; then

mv habitat/setup/etc/* /etc/

fi

# Moving /etc files

mv habitat/setup/etc/* /etc/


# Configuring network settings
echo "Configuring static IP address at 192.168.0.8"

mv 01-netcfg.yaml /etc/netplan/01-netcfg.yaml


