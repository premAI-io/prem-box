#!/usr/bin/env bash

[ ! -n "$BASH_VERSION" ] && echo "You can only run this script with bash, not sh / dash." && exit 1

set -eou pipefail

echo ""
echo -e "🤖 Prem updater"
echo -e "This script will update Prem to latest versions"
echo ""



ORIGINAL_HOME=$(eval echo ~$SUDO_USER)
# Check if the Prem configuration directory exists
if [ ! -f "$ORIGINAL_HOME/prem/config" ]; then
    echo "Prem configuration directory ($ORIGINAL_HOME/prem/config) not found."
    echo "You need to install Prem first. Run 'sudo bash install.sh'."
    exit 1
fi

DEFAULT_PREM_BOX_USER=premai-io
DEFAULT_PREM_BOX_BRANCH=main
DEFAULT_PREM_REGISTRY_BRANCH=main

PREM_BOX_REPO=prem-box
PREM_BOX_USER=${1:-$DEFAULT_PREM_BOX_USER}
PREM_BOX_BRANCH=${2:-$DEFAULT_PREM_BOX_BRANCH}
PREM_REGISTRY_BRANCH=${3:-$DEFAULT_PREM_REGISTRY_BRANCH}
PREM_REGISTRY_URL=https://raw.githubusercontent.com/premAI-io/prem-registry/$PREM_REGISTRY_BRANCH/manifests.json


# update all to latest release images
echo "⬇️ Pulling latest versions..."
curl --silent https://raw.githubusercontent.com/$PREM_BOX_USER/$PREM_BOX_REPO/$PREM_BOX_BRANCH/versions.json -o $ORIGINAL_HOME/prem/versions.json
versions_json=$(cat "$ORIGINAL_HOME"/prem/versions.json)

# Extract the 'app' details
app_version=$(echo "$versions_json" | jq -r '.prem.app.version')
app_image=$(echo "$versions_json" | jq -r '.prem.app.image')
app_digest=$(echo "$versions_json" | jq -r '.prem.app.digest')

echo "Prem-App Version: $app_version"
echo "Prem-App Image: $app_image"
echo "Prem-App Digest: $app_digest"

# Extract the 'daemon' details
daemon_version=$(echo "$versions_json" | jq -r '.prem.daemon.version')
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

echo ""
echo "🔧 Configure Prem..."

# Check if the network exists
if ! docker network inspect prem-gateway >/dev/null 2>&1; then
    docker network create prem-gateway
fi

export PREM_APP_IMAGE=${app_image}:${app_version}@${app_digest}
export PREM_DAEMON_IMAGE=${daemon_image}:${daemon_version}@${daemon_digest}
export PREMG_DNSD_IMAGE=${dnsd_image}:${dnsd_version}@${dnsd_digest}
export PREMG_CONTROLLERD_IMAGE=${controllerd_image}:${controllerd_version}@${controllerd_digest}
export PREMG_AUTHD_IMAGE=${authd_image}:${authd_version}@${authd_digest}
export PREM_REGISTRY_URL=${PREM_REGISTRY_URL}

echo ""
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
    docker-compose -f $ORIGINAL_HOME/prem/docker-compose.premapp.premd.yml -f $ORIGINAL_HOME/prem/docker-compose.gpu.yml -f $ORIGINAL_HOME/prem/docker-compose.premg.yml up -d || exit 1
else
    echo "No NVIDIA GPU detected. Running without gpu support..."
    docker-compose -f $ORIGINAL_HOME/prem/docker-compose.premapp.premd.yml -f $ORIGINAL_HOME/prem/docker-compose.premg.yml up -d || exit 1
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

echo -e "🥳 Your Prem instance is updated to the latest version."
echo ""
echo "Please visit http://$(curl -4s https://ifconfig.io) to get started."
echo ""
echo "You secrets are stored in $ORIGINAL_HOME/prem/secrets"
echo "ie. cat $ORIGINAL_HOME/prem/secrets"