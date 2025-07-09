#!/bin/bash
# extract-patched-war.sh
# Build up to the war-patcher stage and extract the patched WAR
# Usage: ./extract-patched-war.sh [--platform <platform>]

set -e

IMAGE_NAME="jabaws-war-patcher"
CONTAINER_NAME="temp-jabaws-war"
WAR_PATH_IN_CONTAINER="/tmp/jabaws-patched.war"
PLATFORM_ARG=""
PLATFORM_SUFFIX=""

# Parse optional --platform argument
while [[ $# -gt 0 ]]; do
  case $1 in
    --platform)
      PLATFORM_ARG="--platform $2"
      # Replace slashes with underscores for filename safety
      PLATFORM_SUFFIX="-$2"
      PLATFORM_SUFFIX="${PLATFORM_SUFFIX//\//_}"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--platform <platform>]"
      exit 1
      ;;
  esac
done

WAR_PATH_ON_HOST="./jabaws-patched${PLATFORM_SUFFIX}.war"

# Build the Docker image up to the war-patcher stage
docker build $PLATFORM_ARG --target=war-patcher -t "$IMAGE_NAME" .

# Remove any existing container with the same name to avoid conflicts
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  docker rm -f "$CONTAINER_NAME"
fi

# Create a temporary container from the image
docker create --name "$CONTAINER_NAME" "$IMAGE_NAME"

# Copy the patched WAR from the container to the host
docker cp "$CONTAINER_NAME":"$WAR_PATH_IN_CONTAINER" "$WAR_PATH_ON_HOST"

# Clean up the temporary container
docker rm "$CONTAINER_NAME"

echo "Extracted patched WAR to $WAR_PATH_ON_HOST"