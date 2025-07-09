#!/bin/bash
################################################################################
# Quick JABAWS Docker Build Script
#
# This is a simplified version of build.sh for quick builds.
# For advanced options, use the full build.sh script.
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}JABAWS Quick Build${NC}"
echo "Building JABAWS Docker image with default settings..."
echo

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

# Run the full build script with default options
cd "$SCRIPT_DIR"
./build.sh --tag jabaws:latest

echo
echo -e "${GREEN}Quick build completed!${NC}"
echo "To run: docker run -p 8080:8080 jabaws:latest"
