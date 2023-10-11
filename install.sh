#!/usr/bin/env bash

[ ! -n "$BASH_VERSION" ] && echo "You can only run this script with bash, not sh / dash." && exit 1

set -eou pipefail

SCRIPT_VERSION="v0.0.1"

DEFAULT_PREM_BOX_USER=premai-io
DEFAULT_PREM_BOX_BRANCH=main
DEFAULT_PREM_REGISTRY_BRANCH=main

PREM_BOX_REPO=prem-box
PREM_BOX_USER=${1:-$DEFAULT_PREM_BOX_USER}
PREM_BOX_BRANCH=${2:-$DEFAULT_PREM_BOX_BRANCH}
PREM_REGISTRY_BRANCH=${3:-$DEFAULT_PREM_REGISTRY_BRANCH}

ARCH=$(uname -m)
WHO=$(whoami)
DEBUG=0
FORCE=0
NO_TRACK=0

DOCKER_MAJOR=20
DOCKER_MINOR=10
DOCKER_VERSION_OK="nok"

PREM_REGISTRY_URL=https://raw.githubusercontent.com/premAI-io/prem-registry/$PREM_REGISTRY_BRANCH/manifests.json
SENTRY_DSN=https://75592545ad6b472e9ad7c8ff51740b73@o1068608.ingest.sentry.io/4505244431941632

PREM_APP_ID=$(cat /proc/sys/kernel/random/uuid)
PREM_AUTO_UPDATE=false

PREM_CONF_FOUND=$(find ~ -path "$HOME/prem/.env")

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
    echo "Please wait, we are downloading the latest docker compose files from $PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH"
    curl --silent https://raw.githubusercontent.com/$PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH/docker-compose.premg.yml -o $HOME/prem/docker-compose.premg.yml
    curl --silent https://raw.githubusercontent.com/$PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH/docker-compose.premapp.premd.yml -o $HOME/prem/docker-compose.premapp.premd.yml
    curl --silent https://raw.githubusercontent.com/$PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH/docker-compose.gpu.yml -o $HOME/prem/docker-compose.gpu.yml
    curl --silent https://raw.githubusercontent.com/$PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH/versions.json -o $HOME/prem/versions.json
}
# Function to check for NVIDIA GPU
has_gpu() {
    if lspci | grep -i 'NVIDIA' > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
# Function to check for NVIDIA drivers
check_nvidia_driver() {
    if command -v nvidia-smi > /dev/null 2>&1 && which nvidia-container-toolkit > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to install NVIDIA drivers
install_nvidia_drivers() {
    export DEBIAN_FRONTEND=noninteractive
    # Update package list
    sudo apt -qq update -y

    # Install necessary packages for the NVIDIA driver installation
    sudo apt -qq install -y build-essential dkms ubuntu-drivers-common

    # Install the recommended driver
    sudo ubuntu-drivers autoinstall

    # variable and install function for Nvidia-Container Toolkit
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    echo $distribution
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt -qq update -y
    sudo apt install -qq -y nvidia-docker2
    sudo systemctl restart docker

    # Reboot system to take effect
    sudo reboot
}

# Making base directory for prem
if [ ! -d $HOME/prem ]; then
    mkdir $HOME/prem
fi

echo ""
echo -e "🤖 Welcome to Prem installer!"
echo -e "This script will install all requirements to run Prem"
echo ""

# install curl, jq
DEBIAN_FRONTEND=noninteractive sudo apt update -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive sudo apt install -qq jq curl > /dev/null 2>&1

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
# Get the latest version of Docker Compose
DOCKER_COMPOSE_VERSION=$(curl --silent https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)



if [ "$ARCH" == 'arm64' ]; then
    sudo curl --silent -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-aarch64" -o /usr/local/bin/docker-compose
fi
if [ "$ARCH" == 'aarch64' ]; then
    sudo curl --silent -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
fi
if [ "$ARCH" == 'x86_64' ]; then
    sudo curl --silent -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
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
versions_json=$(cat "$HOME"/prem/versions.json)

# Extract the 'app' details
app_version=$(echo "$versions_json" | jq -r '.prem.app.version')
app_image=$(echo "$versions_json" | jq -r '.prem.app.image')
app_digest=$(echo "$versions_json" | jq -r '.prem.app.digest')

echo "Prem-App Version: $app_version"
echo "Prem-App Image: $app_image"
echo "Prem-App Digest: $app_digest"

# Extract the 'daemon' details
daemon_version=$(echo "$versions_json" | jq -r '.prm.daemon.version')
daemon_image=$(echo "$versions_json" | jq -r '.prem.daemon.image')
daemon_digest=$(echo "$versions_json" | jq -r '.prem.daemon.digest')

echo "Prem-Daemon Version: $daemon_version"
echo "Prem-Daemon Image: $daemon_image"
echo "Prem-Daemon Digest: $daemon_digest"

# Extract the 'dnsd' details
dnsd_version=$(echo "$versions_json" | jq -r '.prem.dnsd.version')
dnsd_image=$(echo "$versions_json" | jq -r '.prem.dnsd.image')
dnsd_digest=$(echo "$versions_json" | jq -r '.prem.dnsd.digest')

echo "Dnsd Version: $dnsd_version"
echo "Dnsd Image: $dnsd_image"
echo "Dnsd Digest: $dnsd_digest"

# Extract the 'controllerd' details
controllerd_version=$(echo "$versions_json" | jq -r '.prem.controllerd.version')
controllerd_image=$(echo "$versions_json" | jq -r '.prem.controllerd.image')
controllerd_digest=$(echo "$versions_json" | jq -r '.prem.controllerd.digest')

echo "Controllerd Version: $controllerd_version"
echo "Controllerd Image: $controllerd_image"
echo "Controllerd Digest: $controllerd_digest"

# Extract the 'authd' details
authd_version=$(echo "$versions_json" | jq -r '.prem.authd.version')
authd_image=$(echo "$versions_json" | jq -r '.prem.authd.image')
authd_digest=$(echo "$versions_json" | jq -r '.prem.authd.digest')

echo "Authd Version: $authd_version"
echo "Authd Image: $authd_image"
echo "Authd Digest: $authd_digest"

set -e

echo "🔧 Configure Prem..."

# Check if the network exists
if ! docker network inspect prem-gateway >/dev/null 2>&1; then
    docker network create prem-gateway
fi

export PREM_APP_IMAGE=${app_image}@${app_digest}
export PREM_DAEMON_IMAGE=${daemon_image}@${daemon_digest}
export PREMG_DNSD_IMAGE=${dnsd_image}@${dnsd_digest}
export PREMG_CONTROLLERD_IMAGE=${controllerd_image}@${controllerd_digest}
export PREMG_AUTHD_IMAGE=${authd_image}@${authd_digest}
export SENTRY_DSN=${SENTRY_DSN}
export PREM_REGISTRY_URL=${PREM_REGISTRY_URL}

if ! command -v openssl &> /dev/null
then
    sudo apt-get update -qq
    sudo apt-get install -y openssl
fi

# Generate a random password for the postgres user
POSTGRES_PASSWORD=$(openssl rand -base64 8)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" > $HOME/prem/secrets

# Export the generated password as an environment variable
export POSTGRES_PASSWORD
export LETSENCRYPT_PROD=true
export SERVICES=premd,premapp
export POSTGRES_USER=root
export POSTGRES_PASSWORD=secret
export POSTGRES_DB=dnsd-db
# Generate a random password for the basic auth user
BASIC_AUTH_USER="admin"
BASIC_AUTH_PASS=$(openssl rand -base64 4)
HASH=$(openssl passwd -apr1 $BASIC_AUTH_PASS)
BASIC_AUTH_CREDENTIALS="$BASIC_AUTH_USER:$HASH"
echo "BASIC_AUTH_CREDS=$BASIC_AUTH_USER/$BASIC_AUTH_PASS" >> $HOME/prem/secrets
export BASIC_AUTH_CREDENTIALS


echo "🏁 Starting Prem..."
# Check for GPU and install drivers if necessary
if has_gpu; then
    if ! check_nvidia_driver; then
        echo "NVIDIA GPU detected, but drivers not installed. Installing drivers..."
        echo "This will reboot your system. Please run this script again after reboot."
        install_nvidia_drivers
        exit 0
    fi
    echo "nvidia-smi is available. Running with gpu support..."
    docker-compose -f $HOME/prem/docker-compose.premapp.premd.yml -f $HOME/prem/docker-compose.gpu.yml -f $HOME/prem/docker-compose.premg.yml up -d || exit 1
else
    echo "No NVIDIA GPU detected. Running without gpu support..."
    docker-compose -f $HOME/prem/docker-compose.premapp.premd.yml -f $HOME/prem/docker-compose.premg.yml up -d || exit 1
fi

# Loop to check for 'OK' from curl command with maximum 10 retries
retries=0
while [ $retries -lt 10 ]; do
    response=$(set +e; curl -s --fail http://localhost:8080/ping; set -e)
    if [ "$response" == "OK" ]; then
        echo "Received OK. Proceeding to next step."
        break
    else
        echo "Waiting for OK response..."
        sleep 2
        retries=$((retries + 1))
    fi
done

[ "$response" == "OK" ] || { echo "Failed to receive OK response."; exit 1; }

echo -e "🎉 Congratulations! Your Prem instance is ready to use"
echo ""
echo "Please visit http://$(curl -4s https://ifconfig.io) to get started."
echo "Basic auth user: $BASIC_AUTH_USER"
echo "Basic auth pass: $BASIC_AUTH_PASS"

curl --silent -X POST https://analytics.prem.ninja/api/event \
    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.121 Safari/537.36 OPR/71.0.3770.284' \
    -H 'X-Forwarded-For: 127.0.0.1' \
    -H 'Content-Type: application/json' \
    --data '{"name":"linux_install","url":"https://premai.io","domain":"premai.io"}'
