#!/bin/bash

# Build and push ubersdr-cwskimmer images
# Usage: ./docker.sh [version] [--no-push] [--fresh-driver]
# Example: ./docker.sh 0.9
# Example: ./docker.sh 0.9 --no-push
# Example: ./docker.sh 0.9 --fresh-driver   # re-download the latest CW_Skimmer.zip

set -e

# Parse arguments
VERSION="0.9"
NO_PUSH=false
FRESH_DRIVER=false

for arg in "$@"; do
    case $arg in
        --no-push)
            NO_PUSH=true
            ;;
        --fresh-driver)
            FRESH_DRIVER=true
            ;;
        *)
            VERSION="$arg"
            ;;
    esac
done

IMAGE=madpsy/ubersdr-cwskimmer

echo "Building ubersdr-cwskimmer version $VERSION"

# Fetch latest patt3ch.lst before building so the image contains the newest file
PATT3CH_URL="https://data.reversebeacon.net/downloads/patt3ch/patt3ch.lst"
PATT3CH_DEST="./install/patt3ch/patt3ch.lst"
PATT3CH_MAX_ATTEMPTS=3
PATT3CH_RETRY_DELAY=2

echo "Fetching latest patt3ch.lst from $PATT3CH_URL ..."
PATT3CH_SUCCESS=false
for attempt in $(seq 1 $PATT3CH_MAX_ATTEMPTS); do
    if wget -q -O "${PATT3CH_DEST}.tmp" "$PATT3CH_URL"; then
        mv "${PATT3CH_DEST}.tmp" "$PATT3CH_DEST"
        echo "patt3ch.lst updated successfully (attempt $attempt)"
        PATT3CH_SUCCESS=true
        break
    else
        echo "patt3ch.lst fetch failed (attempt $attempt/$PATT3CH_MAX_ATTEMPTS)"
        rm -f "${PATT3CH_DEST}.tmp"
        if [ $attempt -lt $PATT3CH_MAX_ATTEMPTS ]; then
            sleep $PATT3CH_RETRY_DELAY
        fi
    fi
done

if [ "$PATT3CH_SUCCESS" = "false" ]; then
    echo "Warning: Could not fetch patt3ch.lst after $PATT3CH_MAX_ATTEMPTS attempts — building with existing bundled file"
fi

# Build using docker-compose
# The CW_Skimmer driver comes from a rolling "latest" release URL, so its layer
# stays cached forever unless DRIVER_CACHEBUST changes - --fresh-driver does that,
# invalidating only the driver download onwards (the wine stage stays cached).
if [ "$FRESH_DRIVER" = true ]; then
    echo "Forcing a fresh CW_Skimmer.zip download"
    docker-compose build --build-arg DRIVER_CACHEBUST="$(date +%s)" cwskimmer
else
    docker-compose build
fi

# Tag the built image with version and latest
echo "Tagging image as $IMAGE:$VERSION"
docker tag $IMAGE:latest $IMAGE:$VERSION

echo "Tagging image as $IMAGE:latest"
docker tag $IMAGE:latest $IMAGE:latest

# Push both tags to Docker Hub unless --no-push is specified
if [ "$NO_PUSH" = false ]; then
    echo "Pushing $IMAGE:$VERSION"
    docker push $IMAGE:$VERSION

    echo "Pushing $IMAGE:latest"
    docker push $IMAGE:latest

    echo "Successfully built and pushed $IMAGE:$VERSION and $IMAGE:latest"

    # Commit and push changes to git
    echo "Committing and pushing changes to git..."
    git add -A
    if git diff --staged --quiet; then
        echo "No changes to commit"
    else
        git commit -m "Build and push version $VERSION"
        git push
        echo "Changes pushed to git"
    fi
else
    echo "Successfully built $IMAGE:$VERSION and $IMAGE:latest (skipped push)"
fi
