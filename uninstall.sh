#!/bin/bash

set -e

# Set the directory to $HOME/prem
dir="$HOME/prem"

versions_json=$(cat $dir/versions.json)

# Extract the 'app' details
app_image=$(echo "$versions_json" | jq -r '.prem.app.image')
app_digest=$(echo "$versions_json" | jq -r '.prem.app.digest')

# Extract the 'daemon' details
daemon_image=$(echo "$versions_json" | jq -r '.prem.daemon.image')
daemon_digest=$(echo "$versions_json" | jq -r '.prem.daemon.digest')

# Extract the 'dnsd' details
dnsd_image=$(echo "$versions_json" | jq -r '.prem.dnsd.image')
dnsd_digest=$(echo "$versions_json" | jq -r '.prem.dnsd.digest')

# Extract the 'controllerd' details
controllerd_image=$(echo "$versions_json" | jq -r '.prem.controllerd.image')
controllerd_digest=$(echo "$versions_json" | jq -r '.prem.controllerd.digest')

# Extract the 'authd' details
authd_image=$(echo "$versions_json" | jq -r '.prem.authd.image')
authd_digest=$(echo "$versions_json" | jq -r '.prem.authd.digest')

export PREM_APP_IMAGE=${app_image}@${app_digest}
export PREM_DAEMON_IMAGE=${daemon_image}@${daemon_digest}
export PREMG_DNSD_IMAGE=${dnsd_image}@${dnsd_digest}
export PREMG_CONTROLLERD_IMAGE=${controllerd_image}@${controllerd_digest}
export PREMG_AUTHD_IMAGE=${authd_image}@${authd_digest}
export SENTRY_DSN=${SENTRY_DSN}
export PREM_REGISTRY_URL=${PREM_REGISTRY_URL}

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

    # Run docker-compose down with remove orphans, volumes, and images
    docker-compose -f "$file" down --rmi all --volumes --remove-orphans

    # Check if docker-compose down was successful
    if [ "$?" -ne 0 ]; then
        echo "Failed to process $file. Moving to the next file."
    else
        echo "$file processed successfully."
    fi

done

# Step 2: Find and clean prem-services running on prem-gateway network
containers=$(docker ps --filter network=prem-gateway --format "{{.ID}}")
images=()

# Collecting container images
if [ -n "$containers" ]; then
    echo "Collecting images from containers on prem-gateway network..."
    for container in $containers; do
        image=$(docker inspect "$container" --format "{{.Image}}")
        images+=("$image")
    done
else
    echo "No containers running on prem-gateway network."
    exit 0
fi

# Removing containers
echo "Removing containers on prem-gateway network..."
docker rm -f -v $containers

# Removing images
echo "Removing images used by the containers..."
for image in "${images[@]}"; do
    docker rmi "$image"
done

# Step 3: Remove the prem-gateway network
docker network rm prem-gateway || echo "Failed to remove prem-gateway network. It may not exist."
