#!/bin/bash

# Set the directory to $HOME/prem
dir="$HOME/prem"

# Ensure Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Please start Docker and retry."
    exit 1
fi

# Step 1: Navigate to the directory and clean up services defined in docker-compose files
cd "$dir" || { echo "Directory not found: $dir"; exit 1; }

# Find and loop through all docker-compose files
find . -maxdepth 1 -name 'docker-compose*.yml' -or -name 'docker-compose*.yaml' | while read -r file; do
    echo "Processing $file ..."

    # Run docker-compose down with various options but without --remove-orphans and --volumes
    docker-compose -f "$file" down --rmi all

    # Check if docker-compose down was successful
    if [ "$?" -ne 0 ]; then
        echo "Failed to process $file. Moving to the next file."
    else
        echo "$file processed successfully."
    fi

done

# Step 2: Find and clean prem-services running on prem-gateway network
containers=$(docker ps --filter network=prem-gateway --format "{{.ID}}")
if [ -n "$containers" ]; then
    echo "Removing containers on prem-gateway network..."
    docker rm -f -v $containers

    echo "Removing images used by the containers..."
    for container in $containers; do
        image=$(docker inspect "$container" --format "{{.Image}}")
        docker rmi "$image"
    done
else
    echo "No containers running on prem-gateway network."
fi

# Step 3: Remove the prem-gateway network
docker network rm prem-gateway || echo "Failed to remove prem-gateway network. It may not exist."
