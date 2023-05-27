#!/usr/bin/env bash

[ ! -n "$BASH_VERSION" ] && echo "You can only run this script with bash, not sh / dash." && exit 1

set -eou pipefail

SCRIPT_VERSION="v0.0.1"

## To use later for auto update
USER=premai-io
REPO=prem-box

ARCH=$(uname -m)
WHO=$(whoami)
DEBUG=0
FORCE=0

DOCKER_MAJOR=20
DOCKER_MINOR=10
DOCKER_VERSION_OK="nok"

PREM_APP_ID=$(cat /proc/sys/kernel/random/uuid)
PREM_AUTO_UPDATE=false

PREM_CONF_FOUND=$(find ~ -path '*/prem/.env')

if [ -n "$PREM_CONF_FOUND" ]; then
    eval "$(grep ^PREM_APP_ID= $PREM_CONF_FOUND)"
else
    PREM_CONF_FOUND=${PREM_CONF_FOUND:="$HOME/prem/.env"}
fi

# functions
restartDocker() {
    # Restarting docker daemon
    sudo systemctl daemon-reload
    sudo systemctl restart docker
}
saveConfiguration() {
    echo "PREM_APP_VERSION=${APP_VERSION:-latest}
PREM_DAEMON_VERSION=${DAEMON_VERSION:-latest}
PREM_APP_ID=$PREM_APP_ID
PREM_HOSTED_ON=docker
PREM_AUTO_UPDATE=$PREM_AUTO_UPDATE" >$PREM_CONF_FOUND

  curl --silent https://raw.githubusercontent.com/$USER/$REPO/blob/main/docker-compose.yml -o ~/prem/docker-compose.yml
}

# Making base directory for prem
if [ ! -d ~/prem ]; then
    mkdir ~/prem
fi

echo -e "🤖 Welcome to Prem installer!"
echo -e "This script will install all requirements to run Prem"

# Check docker version
if [ ! -x "$(command -v docker)" ]; then
    if [ $FORCE -eq 1 ]; then
        sh -c "$(curl --silent -fsSL https://get.docker.com)"
        restartDocker
    else
        while true; do
            read -p "Docker Engine not found, should I install it automatically? [Yy/Nn] " yn
            case $yn in
            [Yy]*)
                echo "Installing Docker."
                sh -c "$(curl --silent -fsSL https://get.docker.com)"
                restartDocker
                break
                ;;
            [Nn]*)
                echo "Please install docker manually and update it to the latest, but at least to $DOCKER_MAJOR.$DOCKER_MINOR"
                exit 0
                ;;
            *) echo "Please answer Y or N." ;;
            esac
        done
    fi
fi
SERVER_VERSION=$(sudo docker version -f "{{.Server.Version}}")
SERVER_VERSION_MAJOR=$(echo "$SERVER_VERSION" | cut -d'.' -f 1)
SERVER_VERSION_MINOR=$(echo "$SERVER_VERSION" | cut -d'.' -f 2)

if [[ "$SERVER_VERSION_MAJOR" -gt "$DOCKER_MAJOR" || ("$SERVER_VERSION_MAJOR" -eq "$DOCKER_MAJOR" && "$SERVER_VERSION_MINOR" -ge "$DOCKER_MINOR") ]]; then
    DOCKER_VERSION_OK="ok"
fi

if [ $DOCKER_VERSION_OK == 'nok' ]; then
    echo "Docker version less than $DOCKER_MAJOR.$DOCKER_MINOR, please update it to at least to $DOCKER_MAJOR.$DOCKER_MINOR"
    exit 1
fi


# Downloading docker compose cli plugin from CoolLabs CDN
if [ ! -x ~/.docker/cli-plugins/docker-compose ]; then
    echo "Installing Docker Compose CLI plugin."
    if [ ! -d ~/.docker/cli-plugins/ ]; then
        sudo mkdir -p ~/.docker/cli-plugins/
    fi
    if [ ARCH == 'arm64' ]; then
        sudo curl --silent -SL https://cdn.coollabs.io/bin/linux/arm64/docker-compose-linux-2.6.1 -o ~/.docker/cli-plugins/docker-compose
        sudo chmod +x ~/.docker/cli-plugins/docker-compose
    fi
    if [ ARCH == 'aarch64' ]; then
        sudo curl --silent -SL https://cdn.coollabs.io/bin/linux/aarch64/docker-compose-linux-2.6.1 -o ~/.docker/cli-plugins/docker-compose
        sudo chmod +x ~/.docker/cli-plugins/docker-compose
    fi
    if [ ARCH == 'amd64' ]; then
        sudo curl --silent -SL https://cdn.coollabs.io/bin/linux/amd64/docker-compose-linux-2.6.1 -o ~/.docker/cli-plugins/docker-compose
        sudo chmod +x ~/.docker/cli-plugins/docker-compose
    fi
fi
if [ $FORCE -eq 1 ]; then
    echo 'Updating Prem configuration.'
    saveConfiguration
else
    if [ -f "$PREM_CONF_FOUND" ]; then
        while true; do
            read -p "Prem configuration found (${PREM_CONF_FOUND}). I will overwrite it, okay?  [Yy/Nn] " yn
            case $yn in
            [Yy]*)
                saveConfiguration
                break
                ;;
            [Nn]*)
                break
                ;;
            *) echo "Please answer Y or N." ;;
            esac
        done
    else
        saveConfiguration
    fi
fi
if [ $FORCE -ne 1 ]; then
    echo "👷‍♂️ Installing Prem"
fi


set -e

echo "🏁 Starting Prem..."

# Check if nvidia-smi is available
if command -v nvidia-smi > /dev/null 2>&1; then
    echo "nvidia-smi is available. Running docker-compose.gpu.yml"
    docker-compose -f docker-compose.yml -f docker-compose.gpu.yml up -d
else
    echo "nvidia-smi is not available. Running docker-compose.yml"
    docker-compose up -d
fi

echo -e "🎉 Congratulations! Your Prem instance is ready to use.\n"
echo "Please visit http://$(curl -4s https://ifconfig.io):8000/docs to get started."
