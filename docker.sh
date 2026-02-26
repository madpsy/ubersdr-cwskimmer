#!/bin/bash

# Build and push ubersdr-cwskimmer images
# Usage: ./docker.sh [version] [--no-push]
# Example: ./docker.sh 0.9
# Example: ./docker.sh 0.9 --no-push

set -e

# Parse arguments
VERSION="0.9"
NO_PUSH=false

for arg in "$@"; do
    case $arg in
        --no-push)
            NO_PUSH=true
            ;;
        *)
            VERSION="$arg"
            ;;
    esac
done

IMAGE=madpsy/ubersdr-cwskimmer

echo "Building ubersdr-cwskimmer version $VERSION"

# Build using docker-compose
docker-compose build

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
