#!/bin/bash

NETWORK_NAME="prem-gateway"

# Ask if the user wants a "yes to all" approach.
read -p "Do you want to say 'yes' to all and proceed with a full uninstall without further confirmations? (y/n): " yes_to_all

# Helper function to check if yes to all was selected.
should_proceed() {
    if [ "$yes_to_all" == "y" ]; then
        echo "y"
    else
        read -p "$1 (y/n): " response
        echo "$response"
    fi
}

# Stop and remove containers and their associated volumes on the network
containers_to_remove=$(docker network inspect $NETWORK_NAME --format '{{range .Containers}}{{.Name}} {{end}}')
if [[ ! -z "$containers_to_remove" ]]; then
    docker stop $containers_to_remove
    docker rm -v $containers_to_remove # the -v flag removes associated anonymous volumes
fi

# Optionally remove the network itself
remove_network=$(should_proceed "Do you want to remove the network $NETWORK_NAME?")
if [ "$remove_network" == "y" ]; then
    docker network rm $NETWORK_NAME
fi

# Check if the datadir should be removed.
remove_datadir=$(should_proceed "Do you want to remove the datadir located in $HOME/prem? (This deletes data!)")
if [ "$remove_datadir" == "y" ]; then
    rm -rf $HOME/prem
fi

echo "Uninstallation completed!"
