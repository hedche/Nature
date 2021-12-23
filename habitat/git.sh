#!/bin/bash 

# Author: Monty Rhodes
# Created: 23/12/2021
# This script will either setup ssh keys or push

read -p "Are you setting up ssh or pushing? " $option

if [ "$option" = "ssh" ]; then

	ssh-keygen -t ed25519 -C "montyrhodes8@gmail.com"

elif [ "$option" = "push" ]; then
	git add .
fi
