#!/bin/bash
# extract-patched-war.sh
# Build up to the war-patcher stage and extract the patched WAR
# Usage: ./extract-patched-war.sh [--platform <platform>]


set -e

# Ensure script runs from its own directory for correct build context
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Container engine. Podman and Docker are interchangeable for everything this
# script does, so pick whichever is present rather than hard-coding one. Set
# CONTAINER_ENGINE to override.
ENGINE="${CONTAINER_ENGINE:-}"
if [[ -z "$ENGINE" ]]; then
    if command -v podman &> /dev/null; then
        ENGINE=podman
    elif command -v docker &> /dev/null; then
        ENGINE=docker
    else
        echo "Error: neither podman nor docker found in PATH" >&2
        exit 1
    fi
fi

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

WAR_PATH_ON_HOST="$SCRIPT_DIR/jabaws-patched${PLATFORM_SUFFIX}.war"

# Build the image up to the war-patcher stage
"$ENGINE" build $PLATFORM_ARG --target=war-patcher -t "$IMAGE_NAME" .

# Remove any existing container with the same name to avoid conflicts
if "$ENGINE" ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}$"; then
  "$ENGINE" rm -f "$CONTAINER_NAME"
fi

# Create a temporary container from the image
"$ENGINE" create --name "$CONTAINER_NAME" "$IMAGE_NAME"

# Copy the patched WAR from the container to the host
"$ENGINE" cp "$CONTAINER_NAME":"$WAR_PATH_IN_CONTAINER" "$WAR_PATH_ON_HOST"

# Clean up the temporary container
"$ENGINE" rm "$CONTAINER_NAME"

echo "Extracted patched WAR to $WAR_PATH_ON_HOST"