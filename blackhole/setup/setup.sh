#!/bin/bash

# Author: Monty Rhodes
# Created: 23/12/2021
# This setup script will move all the required config files over 

echo "Running setup for habitat..."

mv hosts /etc/
mv hostname /etc/
mv fstab /etc/

# Configuring network settings
echo "Configuring static IP address at 192.168.0.8"

mv 01-netcfg.yaml /etc/netplan/01-netcfg.yaml

netplan apply

