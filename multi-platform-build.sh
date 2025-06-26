#!/bin/bash
################################################################################
# JABAWS Multi-Platform Docker Build Script
#
# This script builds JABAWS Docker images for both AMD64 and ARM64 architectures
# and pushes them as a multi-platform manifest to a Docker registry.
#
# Requirements:
# - Docker with Buildx support
# - Access to a Docker registry (Docker Hub, etc.)
# - Logged in to the registry (docker login)
#
# Usage:
#   ./multi-platform-build.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -t, --tag TAG           Docker image tag (default: jabaws:latest)
#   -c, --clean             Clean build (remove existing dependencies)
#   -n, --no-cache          Build without Docker cache
#   -v, --verbose           Enable verbose output
#   --registry REGISTRY     Docker registry (e.g., docker.io, ghcr.io)
#   --check-only           Only check prerequisites, don't build
#
# Examples:
#   ./multi-platform-build.sh --tag myregistry/jabaws:v2.2
#   ./multi-platform-build.sh --clean --verbose
#   ./multi-platform-build.sh --check-only
################################################################################

set -e

# Default values
IMAGE_TAG="jabaws:latest"
CLEAN_BUILD=false
NO_CACHE=false
VERBOSE=false
REGISTRY=""
CHECK_ONLY=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

print_header() {
    echo -e "${BOLD}${BLUE}$1${NC}"
}

# Function to show help
show_help() {
    cat << EOF
JABAWS Multi-Platform Docker Build Script

This script builds JABAWS Docker images for both AMD64 and ARM64 architectures
and pushes them as a multi-platform manifest to a Docker registry.

Requirements:
- Docker with Buildx support
- Access to a Docker registry (Docker Hub, etc.)
- Logged in to the registry (docker login)

Usage:
  ./multi-platform-build.sh [OPTIONS]

Options:
  -h, --help              Show this help message
  -t, --tag TAG           Docker image tag (default: jabaws:latest)
  -c, --clean             Clean build (remove existing dependencies)
  -n, --no-cache          Build without Docker cache
  -v, --verbose           Enable verbose output
  --registry REGISTRY     Docker registry (e.g., docker.io, ghcr.io)
  --check-only           Only check prerequisites, don't build

Examples:
  ./multi-platform-build.sh --tag myregistry/jabaws:v2.2
  ./multi-platform-build.sh --clean --verbose
  ./multi-platform-build.sh --check-only

Prerequisites Check:
  ./multi-platform-build.sh --check-only

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local all_good=true
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        all_good=false
    else
        print_success "Docker is available"
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        all_good=false
    else
        print_success "Docker daemon is running"
    fi
    
    # Check Buildx
    if ! docker buildx version &> /dev/null; then
        print_error "Docker Buildx is not available"
        print_error "Multi-platform builds require Docker Buildx"
        all_good=false
    else
        print_success "Docker Buildx is available"
    fi
    
    # Check builder platforms
    local available_platforms
    available_platforms=$(docker buildx inspect --bootstrap 2>/dev/null | grep "Platforms:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    
    if ! echo "$available_platforms" | grep -q "linux/amd64"; then
        print_error "Builder does not support linux/amd64 platform"
        all_good=false
    else
        print_success "linux/amd64 platform supported"
    fi
    
    if ! echo "$available_platforms" | grep -q "linux/arm64"; then
        print_error "Builder does not support linux/arm64 platform"
        all_good=false
    else
        print_success "linux/arm64 platform supported"
    fi
    
    # Check registry login (if tag suggests remote registry)
    if [[ "$IMAGE_TAG" == *"/"* ]]; then
        local registry_host
        registry_host=$(echo "$IMAGE_TAG" | cut -d'/' -f1)
        
        if [[ "$registry_host" != "docker.io" && "$registry_host" != *"."* ]]; then
            # Likely Docker Hub format (username/repo)
            registry_host="docker.io"
        fi
        
        print_status "Checking registry authentication for $registry_host..."
        
        # Try to get registry info (this will fail if not logged in)
        if docker buildx imagetools inspect --raw "$IMAGE_TAG" &> /dev/null; then
            print_success "Registry authentication verified"
        else
            print_warning "Cannot verify registry authentication"
            print_warning "Make sure you're logged in with: docker login $registry_host"
        fi
    fi
    
    if [[ "$all_good" == true ]]; then
        print_success "All prerequisites satisfied!"
        return 0
    else
        print_error "Some prerequisites are missing"
        return 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -n|--no-cache)
            NO_CACHE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Update tag with registry if provided
if [[ -n "$REGISTRY" && "$IMAGE_TAG" != *"/"* ]]; then
    IMAGE_TAG="$REGISTRY/$IMAGE_TAG"
fi

print_header "JABAWS Multi-Platform Build"
echo "Building for platforms: linux/amd64, linux/arm64"
echo "Image tag: $IMAGE_TAG"
echo

# Check prerequisites
if ! check_prerequisites; then
    exit 1
fi

# Exit if only checking
if [[ "$CHECK_ONLY" == true ]]; then
    print_success "Prerequisites check completed successfully!"
    exit 0
fi

# Build arguments for main build script
BUILD_ARGS=()
BUILD_ARGS+=("--multi-platform")
BUILD_ARGS+=("--push")
BUILD_ARGS+=("--tag" "$IMAGE_TAG")

if [[ "$CLEAN_BUILD" == true ]]; then
    BUILD_ARGS+=("--clean")
fi

if [[ "$NO_CACHE" == true ]]; then
    BUILD_ARGS+=("--no-cache")
fi

if [[ "$VERBOSE" == true ]]; then
    BUILD_ARGS+=("--verbose")
fi

# Execute the main build script
print_header "Starting Multi-Platform Build"
print_status "Executing: ./build.sh ${BUILD_ARGS[*]}"

cd "$SCRIPT_DIR"
if ./build.sh "${BUILD_ARGS[@]}"; then
    print_success "Multi-platform build completed successfully!"
    echo
    echo "Image available for both architectures:"
    echo "  docker run -p 8080:8080 $IMAGE_TAG"
    echo
    echo "Docker will automatically pull the correct architecture for your platform."
else
    print_error "Multi-platform build failed"
    exit 1
fi
