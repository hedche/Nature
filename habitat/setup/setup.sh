#!/bin/bash

echo "RUNNING SETUP FOR habitat"


# Moving /etc files

mv hosts /etc/hosts

mv hostname /etc/hostname

mv fstab /etc/fstab


# Configuring network settings
echo "Configuring static IP address at 192.168.0.8"

mv 01-netcfg.yaml /etc/netplan/01-netcfg.yaml


