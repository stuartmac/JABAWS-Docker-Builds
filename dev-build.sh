#!/bin/bash
################################################################################
# JABAWS Development Build Script
#
# Optimized for development with faster build times:
# - Skips dependency re-download unless forced
# - Uses build cache by default
# - Provides quick rebuild options
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="jabaws:dev"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[DEV]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
JABAWS Development Build Script

Optimized for development with faster build times.

Usage:
  ./dev-build.sh [OPTIONS]

Options:
  -h, --help      Show this help message
  -c, --clean     Clean build (re-download dependencies, no cache)
  -f, --fast      Fast build (skip dependency check, use cache)
  -r, --run       Build and run the container immediately
  -s, --stop      Stop any running jabaws-dev container
  --logs          Show logs from running container

Examples:
  ./dev-build.sh           # Standard development build
  ./dev-build.sh --fast    # Skip checks, use cache
  ./dev-build.sh --clean   # Full clean rebuild
  ./dev-build.sh --run     # Build and run immediately

EOF
}

# Default options
CLEAN_BUILD=false
FAST_BUILD=false
RUN_AFTER_BUILD=false
STOP_CONTAINER=false
SHOW_LOGS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -f|--fast)
            FAST_BUILD=true
            shift
            ;;
        -r|--run)
            RUN_AFTER_BUILD=true
            shift
            ;;
        -s|--stop)
            STOP_CONTAINER=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Stop container if requested
if [[ "$STOP_CONTAINER" == true ]]; then
    print_info "Stopping jabaws-dev container..."
    docker stop jabaws-dev 2>/dev/null || print_warning "Container jabaws-dev not running"
    docker rm jabaws-dev 2>/dev/null || print_warning "Container jabaws-dev not found"
    exit 0
fi

# Show logs if requested
if [[ "$SHOW_LOGS" == true ]]; then
    print_info "Showing logs for jabaws-dev container..."
    docker logs -f jabaws-dev 2>/dev/null || print_error "Container jabaws-dev not found or not running"
    exit 0
fi

print_info "Starting JABAWS development build..."

# Check Docker
if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running"
    exit 1
fi

cd "$SCRIPT_DIR"

# Build arguments
BUILD_ARGS=()

if [[ "$CLEAN_BUILD" == true ]]; then
    BUILD_ARGS+=("--clean" "--no-cache")
    print_info "Clean build requested"
elif [[ "$FAST_BUILD" == true ]]; then
    BUILD_ARGS+=("--skip-deps")
    print_info "Fast build requested (skipping dependency checks)"
fi

BUILD_ARGS+=("--tag" "$IMAGE_TAG")

# Execute build
print_info "Building with: ./build.sh ${BUILD_ARGS[*]}"
if ./build.sh "${BUILD_ARGS[@]}"; then
    print_success "Development build completed: $IMAGE_TAG"
else
    print_error "Build failed"
    exit 1
fi

# Run container if requested
if [[ "$RUN_AFTER_BUILD" == true ]]; then
    print_info "Stopping any existing jabaws-dev container..."
    docker stop jabaws-dev 2>/dev/null || true
    docker rm jabaws-dev 2>/dev/null || true
    
    print_info "Starting new jabaws-dev container..."
    docker run -d \
        --name jabaws-dev \
        -p 8080:8080 \
        "$IMAGE_TAG"
    
    print_success "Container started: jabaws-dev"
    print_info "JABAWS will be available at: http://localhost:8080/jabaws"
    print_info "Use './dev-build.sh --logs' to view container logs"
    print_info "Use './dev-build.sh --stop' to stop the container"
fi
