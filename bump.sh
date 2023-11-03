#!/bin/bash

owner="premai-io"

app="app"
app_repo="prem-app"
app_image="prem-app"

daemon="daemon"
daemon_repo="prem-daemon"
daemon_image="premd"

dnsd="dnsd"
dnsd_repo="prem-gateway"
dnsd_image="dnsd"

controllerd="controllerd"
controllerd_repo="prem-gateway"
controllerd_image="controllerd"

auth="authd"
auth_repo="prem-gateway"
auth_image="authd"

# JSON file
json_file="versions.json"

# Function to fetch latest GitHub tag and Docker image digest
bump_to_latest_tag() {
    # Fetch latest release tag from GitHub
    latest_release=$(curl -s https://api.github.com/repos/${owner}/${1}/releases/latest | jq -r .tag_name)
    echo "Latest release tag: $latest_release"

    # Pull the Docker image from GitHub Container Registry
    image_with_tag=ghcr.io/${owner}/${3}:${latest_release}
    echo "Pulling image: $image_with_tag"
    docker pull ${image_with_tag} &> /dev/null

    # Get the Docker image digest
    image_digest=$(docker inspect --format='{{.RepoDigests}}' ${image_with_tag} | awk -F '@' '{print $2}' | tr -d '[]')
    echo "Image digest: $image_digest"

    # Store only the base image name without the tag
    base_image=ghcr.io/${owner}/${3}

    # Update JSON with new tag, digest, and base image name
    jq --arg rep "$2" --arg ver "$latest_release" --arg img "$base_image" --arg dig "$image_digest" \
    '.prem[$rep].version = $ver | .prem[$rep].digest = $dig | .prem[$rep].image = $img' $json_file > temp.json && mv temp.json $json_file
}

bump_to_latest_tag $app_repo $app $app_image
bump_to_latest_tag $daemon_repo $daemon $daemon_image
bump_to_latest_tag $dnsd_repo $dnsd $dnsd_image
bump_to_latest_tag $controllerd_repo $controllerd $controllerd_image
bump_to_latest_tag $auth_repo $auth $auth_image


# Function to ask for user confirmation
confirm_commit() {
    while true; do
        read -p "Do you want to commit and push changes? (yes/no): " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "Exiting without committing."; exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# ... [previous code for bump_to_latest_tag calls]

# Check for changes in the repository
if [ -z "$(git diff -- $json_file)" ]; then
    echo "No changes detected."
    exit 0
fi

# Ask for user confirmation
confirm_commit

## Commit & Push to main
git add $json_file
git commit -S -m "Bump to latest releases"
git push origin main





