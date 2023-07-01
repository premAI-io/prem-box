#!/usr/bin/env bash

[ ! -n "$BASH_VERSION" ] && echo "You can only run this script with bash, not sh / dash." && exit 1

set -eou pipefail

PREM_REGISTRY_URL=https://raw.githubusercontent.com/premAI-io/prem-registry/main/manifests.json
SENTRY_DSN=https://75592545ad6b472e9ad7c8ff51740b73@o1068608.ingest.sentry.io/4505244431941632

SCRIPT_VERSION="v0.0.1"

USER=premai-io
REPO=prem-box

ARCH=$(uname -m)
WHO=$(whoami)
DEBUG=0
FORCE=0
NO_TRACK=0

DOCKER_MAJOR=20
DOCKER_MINOR=10
DOCKER_VERSION_OK="nok"

PREM_APP_ID=$(cat /proc/sys/kernel/random/uuid)
PREM_AUTO_UPDATE=false

PREM_CONF_FOUND=$(find ~ -path '*/prem/.env')

if [ $NO_TRACK -eq 1 ]; then
    SENTRY_DSN=''
fi

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
    # write configuration to file
    echo "PREM_APP_ID=$PREM_APP_ID
PREM_HOSTED_ON=docker
PREM_AUTO_UPDATE=$PREM_AUTO_UPDATE" >$PREM_CONF_FOUND

    # pull latest docker compose file from main branches
    curl --silent https://raw.githubusercontent.com/$USER/$REPO/main/docker-compose.yml -o ~/prem/docker-compose.yml
    curl --silent https://raw.githubusercontent.com/$USER/$REPO/main/docker-compose.gpu.yml -o ~/prem/docker-compose.gpu.yml
    curl --silent https://raw.githubusercontent.com/$USER/$REPO/main/Caddyfile -o ~/prem/Caddyfile
}
# variable and install function for Nvidia-Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
echo $distribution
installNvidiaContainerToolkit(){
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    DEBIAN_FRONTEND=noninteractive sudo apt-get -qq update -y
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -qq -y nvidia-docker2
    sudo systemctl restart docker
}

# Making base directory for prem
if [ ! -d ~/prem ]; then
    mkdir ~/prem
fi

echo ""
echo -e "🤖 Welcome to Prem installer!"
echo -e "This script will install all requirements to run Prem"
echo ""

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


# Function to compare version numbers
function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

# Check Docker Compose standalone CLI version
echo "Check Docker Compose standalone CLI version"

set +e  # disable exit on error
CURRENT_VERSION=$(docker-compose -v 2>/dev/null | awk '{print $3}' | sed 's/,//' || echo "")
set -e  # re-enable exit on error

if [ -n "$CURRENT_VERSION" ]; then
    if version_gt 1.18.0 $CURRENT_VERSION; then
        echo "Current Docker Compose version is lower than 1.18.0, upgrading..."
        sudo rm $(which docker-compose)
    else
        echo "Docker Compose is up to date."
    fi
else
    echo "Installing Docker Compose."
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
# we need jq
DEBIAN_FRONTEND=noninteractive sudo apt -qq update -y 
DEBIAN_FRONTEND=noninteractive sudo apt -qq install -y  jq
# Get the latest version of Docker Compose
DOCKER_COMPOSE_VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)



if [ "$ARCH" == 'arm64' ]; then
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-aarch64" -o /usr/local/bin/docker-compose
fi
if [ "$ARCH" == 'aarch64' ]; then
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
fi
if [ "$ARCH" == 'x86_64' ]; then
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
fi

sudo chmod +x /usr/local/bin/docker-compose

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

echo "⬇️ Pulling latest version..."
versions_json=$(curl --silent https://raw.githubusercontent.com/premAI-io/prem-box/main/versions.json)

# Extract the 'app' details
app_version=$(echo "$versions_json" | jq -r '.prem.app.version')
app_image=$(echo "$versions_json" | jq -r '.prem.app.image')
app_digest=$(echo "$versions_json" | jq -r '.prem.app.digest')

echo "App Version: $app_version"
echo "App Image: $app_image"
echo "App Digest: $app_digest"

# Extract the 'daemon' details
daemon_version=$(echo "$versions_json" | jq -r '.prem.daemon.version')
daemon_image=$(echo "$versions_json" | jq -r '.prem.daemon.image')
daemon_digest=$(echo "$versions_json" | jq -r '.prem.daemon.digest')

echo "Daemon Version: $daemon_version"
echo "Daemon Image: $daemon_image"
echo "Daemon Digest: $daemon_digest"

set -e

echo "🏁 Starting Prem..."

export PREM_APP_IMAGE=${app_image}:${app_version}@${app_digest}
export PREM_DAEMON_IMAGE=${daemon_image}:${daemon_version}@${daemon_digest}
export SENTRY_DSN=${SENTRY_DSN}
export PREM_REGISTRY_URL=${PREM_REGISTRY_URL}
# Check if nvidia-smi is available
if command -v nvidia-smi > /dev/null 2>&1; then
    if [ $(which nvidia-container-toolkit) ]; then
        echo "nvidia-container toolkit is available"
    else
        echo "nvidia-container toolkit is needed for GPU usage inside a container"
        echo "Installing nvidia-container toolkit"
        installNvidiaContainerToolkit
    fi
    echo "nvidia-smi is available. Running docker-compose.gpu.yml"
    docker-compose -f ~/prem/docker-compose.yml -f ~/prem/docker-compose.gpu.yml up -d
else
    echo "nvidia-smi is not available. Running docker-compose.yml"
    docker-compose -f ~/prem/docker-compose.yml up -d
fi

echo -e "🎉 Congratulations! Your Prem instance is ready to use"
echo "Please visit http://$(curl -4s https://ifconfig.io):8000 to get started."

curl --silent -X POST https://analytics.prem.ninja/api/event \
    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.121 Safari/537.36 OPR/71.0.3770.284' \
    -H 'X-Forwarded-For: 127.0.0.1' \
    -H 'Content-Type: application/json' \
    --data '{"name":"linux_install","url":"https://premai.io","domain":"premai.io"}'
