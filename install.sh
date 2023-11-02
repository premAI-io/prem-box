#!/usr/bin/env bash
test ! -n "$BASH_VERSION" && echo >&2 "You can only run this script with bash, not sh / dash." && exit 1
set -eou pipefail
SCRIPT_VERSION="v0.2.0"

# parse CLI options
PREM_BOX_SLUG=premai-io/prem-box/main
PREM_REGISTRY_SLUG=premAI-io/prem-registry/main
FORCE=0
NO_TRACK=0
PREM_AUTO_UPDATE=0
while getopts ":b:r:fnu" arg; do
  case $arg in
    b) # <box slug>, default "premai-io/prem-box/main"
      PREM_BOX_SLUG="${OPTARG}" ;;
    r) # <registry slug>, default "premAI-io/prem-registry/main"
      PREM_REGISTRY_SLUG="${OPTARG}" ;;
    f) # force (re)install
      FORCE=1 ;;
    n) # disable tracking
      NO_TRACK=1 ;;
    u) # auto-update docker images
      PREM_AUTO_UPDATE=1 ;;
    *) # print help
      echo >&2 "$0 $SCRIPT_VERSION usage:" && sed -nr "s/^ +(\w)\) # /  -\1  /p" $0; exit 1 ;;
  esac
done

DOCKER_MAJOR=20
DOCKER_MINOR=10
DOCKER_VERSION_OK="nok"

PREM_REGISTRY_URL=https://raw.githubusercontent.com/$PREM_REGISTRY_SLUG/manifests.json
SENTRY_DSN=https://75592545ad6b472e9ad7c8ff51740b73@o1068608.ingest.sentry.io/4505244431941632

PREM_APP_ID=$(cat /proc/sys/kernel/random/uuid)
ORIGINAL_HOME=$(eval echo ~$SUDO_USER)

PREM_CONF_FOUND=$(find ~ -path "$ORIGINAL_HOME/prem/config")
if test -n "$PREM_CONF_FOUND" ; then
  eval "$(grep ^PREM_APP_ID= $PREM_CONF_FOUND)"
else
  PREM_CONF_FOUND=${PREM_CONF_FOUND:="$ORIGINAL_HOME/prem/config"}
fi

if test $NO_TRACK = 1 ; then
  SENTRY_DSN=''
fi

# functions
restartDocker() {
  sudo systemctl daemon-reload
  sudo systemctl restart docker
}
saveConfiguration() {
  # write configuration to file
  echo "PREM_APP_ID=$PREM_APP_ID
PREM_HOSTED_ON=docker
PREM_AUTO_UPDATE=$PREM_AUTO_UPDATE" >$PREM_CONF_FOUND

  # pull latest docker compose file from main branches
  echo "Please wait, we are downloading the latest docker compose files from $PREM_BOX_SLUG"
  for f in docker-compose.premg.yml docker-compose.premapp.premd.yml docker-compose.gpu.yml docker-compose.autoupdate.yml versions.json; do
    curl -fsSL https://raw.githubusercontent.com/$PREM_BOX_SLUG/$f -o $ORIGINAL_HOME/prem/$f
  done
}
has_gpu() {
  lspci | grep -i 'NVIDIA' > /dev/null 2>&1
}
check_nvidia_driver() {
  command -v nvidia-smi > /dev/null 2>&1 && which nvidia-container-toolkit > /dev/null 2>&1
}
install_nvidia_drivers() {
  # Update package list
  DEBIAN_FRONTEND=noninteractive sudo apt -qq update
  # Install necessary packages for the NVIDIA driver installation
  DEBIAN_FRONTEND=noninteractive sudo apt -qq install -y build-essential dkms ubuntu-drivers-common

  # Install the recommended driver
  sudo ubuntu-drivers autoinstall

  # variable and install function for Nvidia-Container Toolkit
  distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
  echo $distribution
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -
  curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  DEBIAN_FRONTEND=noninteractive sudo apt -qq update
  DEBIAN_FRONTEND=noninteractive sudo apt -qq install -y nvidia-docker2
  sudo systemctl restart docker

  # Reboot system to take effect
  sudo reboot
}

# Making base directory for prem
mkdir -p $ORIGINAL_HOME/prem

echo "==="
echo "🤖 Welcome to Prem installer!"
echo "This script will install all requirements to run Prem"
echo "==="

# install curl, jq
DEBIAN_FRONTEND=noninteractive sudo apt -qq update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive sudo apt -qq install -y jq curl > /dev/null 2>&1

# Check docker version
if test ! -x "$(command -v docker)" ; then
  if test $FORCE -eq 1 ; then
    sh -c "$(curl -fsSL https://get.docker.com)"
    restartDocker
  else
    while true; do
      read -p "Docker Engine not found, should I install it automatically? [Yy/Nn] " yn
      case $yn in
        [Yy]*)
          echo "Installing Docker."
          sh -c "$(curl -fsSL https://get.docker.com)"
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
  echo >&2 "Docker version less than $DOCKER_MAJOR.$DOCKER_MINOR, please update it to at least to $DOCKER_MAJOR.$DOCKER_MINOR"
  exit 1
fi

# Function to compare version numbers
function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

# Check Docker Compose standalone CLI version
echo "Check Docker Compose standalone CLI version"

set +e  # disable exit on error
CURRENT_VERSION=$(docker-compose -v 2>/dev/null | awk '{print $3}' | sed 's/,//' || echo "")
set -e  # re-enable exit on error

if test -n "$CURRENT_VERSION" ; then
  if version_gt 1.18.0 $CURRENT_VERSION; then
    echo "Current Docker Compose version is lower than 1.18.0, upgrading..."
    sudo rm $(which docker-compose)
  else
    echo "Docker Compose is up to date."
  fi
else
  echo "Installing Docker Compose."
fi

# Get the latest version of Docker Compose
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
DOCKER_COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | jq .name -r)
case "$ARCH" in
  arm64|aarch64)
    sudo curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-aarch64" -o /usr/local/bin/docker-compose
    ;;
  x86_64)
    sudo curl -fsSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-${OS}-${ARCH}" -o /usr/local/bin/docker-compose
    ;;
esac
sudo chmod +x /usr/local/bin/docker-compose

if test $FORCE -eq 1 ; then
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
if test $FORCE -ne 1 ; then
  echo ""
  echo "👷‍♂️ Installing Prem"
fi

echo "⬇️ Pulling latest version..."
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
export SENTRY_DSN
export PREM_REGISTRY_URL

if ! command -v openssl &> /dev/null ; then
  DEBIAN_FRONTEND=noninteractive sudo apt -qq update
  DEBIAN_FRONTEND=noninteractive sudo apt -qq install -y openssl
fi

# Generate a random password for the postgres user
POSTGRES_PASSWORD=$(openssl rand -base64 8)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" > $ORIGINAL_HOME/prem/secrets

# Export the generated password as an environment variable
export POSTGRES_PASSWORD
export LETSENCRYPT_PROD=true
export SERVICES=premd,premapp
export POSTGRES_USER=root
export POSTGRES_DB=dnsd-db

echo ""
echo "🏁 Starting Prem..."
DCC="docker-compose -f $ORIGINAL_HOME/prem/docker-compose.premapp.premd.yml -f $ORIGINAL_HOME/prem/docker-compose.premg.yml"
# Check for PREM_AUTO_UPDATE and run watchtower if necessary
if test $PREM_AUTO_UPDATE = 1; then
  echo "Using :latest images & auto-updating"
  export PREM_APP_IMAGE=ghcr.io/premai-io/prem-app:latest
  export PREM_DAEMON_IMAGE=ghcr.io/premai-io/premd:latest
  export PREMG_DNSD_IMAGE=ghcr.io/premai-io/dnsd:latest
  export PREMG_CONTROLLERD_IMAGE=ghcr.io/premai-io/controllerd:latest
  export PREMG_AUTHD_IMAGE=ghcr.io/premai-io/authd:latest
  DCC="$DCC -f docker-compose.autoupdate.yml"
fi
# Check for GPU and install drivers if necessary
if has_gpu; then
  if ! check_nvidia_driver; then
    echo "NVIDIA GPU detected, but drivers not installed. Installing drivers..."
    echo "This will reboot your system. Please run this script again after reboot."
    install_nvidia_drivers
    exit 0
  fi
  echo "nvidia-smi is available. Running with gpu support..."
  $DCC -f $ORIGINAL_HOME/prem/docker-compose.gpu.yml up -d || exit 1
else
  echo "No NVIDIA GPU detected. Running without gpu support..."
  $DCC up -d || exit 1
fi

# Loop to check for 'OK' from curl command with maximum 10 retries
retries=0
while test $retries -lt 10 ; do
  response=$(set +e; curl -fs http://localhost:8080/ping; set -e)
  if test "$response" = OK ; then
    echo "Received OK. Proceeding to next step."
    break
  else
    echo "Waiting for OK response..."
    sleep 2
    retries=$((retries + 1))
  fi
done

test "$response" = OK || { echo "Failed to receive OK response."; exit 1; }

echo "🎉 Congratulations! Your Prem instance is ready to use"
echo ""
echo "Please visit http://$(curl -4s https://ifconfig.io) to get started."
echo ""
echo "You secrets are stored in $ORIGINAL_HOME/prem/secrets"
echo "ie. cat $ORIGINAL_HOME/prem/secrets"

if test $NO_TRACK -ne 1 ; then
  curl --silent -X POST https://analytics.prem.ninja/api/event \
    -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.121 Safari/537.36 OPR/71.0.3770.284' \
    -H 'X-Forwarded-For: 127.0.0.1' \
    -H 'Content-Type: application/json' \
    --data '{"name":"linux_install","url":"https://premai.io","domain":"premai.io"}'
fi
