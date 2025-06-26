#!/bin/bash
################################################################################
# JABAWS Docker Build Script
#
# This script automates the complete Docker build process for JABAWS,
# including dependency preparation and multi-architecture support.
#
# Usage:
#   ./build.sh [OPTIONS]
#
# Options:
#   -h, --help              Show this help message
#   -p, --platform PLATFORM Specify target platform (default: auto-detect)
#                           Options: linux/amd64, linux/arm64, auto
#   -t, --tag TAG           Docker image tag (default: jabaws:latest)
#   -c, --clean             Clean build (remove existing dependencies)
#   -n, --no-cache          Build without Docker cache
#   -d, --deps-only         Only prepare dependencies, don't build Docker image
#   -v, --verbose           Enable verbose output
#   --skip-deps             Skip dependency preparation (assume already done)
#   --push                  Push image to registry after build
#
# Examples:
#   ./build.sh                                    # Auto-detect platform
#   ./build.sh --platform linux/amd64           # Build for AMD64
#   ./build.sh --platform linux/arm64           # Build for ARM64
#   ./build.sh --tag jabaws:v2.2 --no-cache     # Custom tag, no cache
#   ./build.sh --clean --verbose                 # Clean build with verbose output
################################################################################

set -e  # Exit on any error

# Default values
PLATFORM="auto"
IMAGE_TAG="jabaws:latest"
CLEAN_BUILD=false
NO_CACHE=false
DEPS_ONLY=false
VERBOSE=false
SKIP_DEPS=false
PUSH_IMAGE=false
MULTI_PLATFORM=false
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
JABAWS Docker Build Script

This script automates the complete Docker build process for JABAWS,
including dependency preparation and multi-architecture support.

Usage:
  ./build.sh [OPTIONS]

Options:
  -h, --help              Show this help message
  -p, --platform PLATFORM Specify target platform (default: auto-detect)
                          Options: linux/amd64, linux/arm64, auto
  -t, --tag TAG           Docker image tag (default: jabaws:latest)
  -c, --clean             Clean build (remove existing dependencies)
  -n, --no-cache          Build without Docker cache
  -d, --deps-only         Only prepare dependencies, don't build Docker image
  -v, --verbose           Enable verbose output
  --skip-deps             Skip dependency preparation (assume already done)
  --push                  Push image to registry after build
  --multi-platform        Build for both linux/amd64 and linux/arm64
                          (requires --push, creates manifest for both platforms)

Examples:
  ./build.sh                                    # Auto-detect platform
  ./build.sh --platform linux/amd64           # Build for AMD64
  ./build.sh --platform linux/arm64           # Build for ARM64
  ./build.sh --tag jabaws:v2.2 --no-cache     # Custom tag, no cache
  ./build.sh --clean --verbose                 # Clean build with verbose output
  ./build.sh --multi-platform --push          # Multi-platform build and push

Platform Detection:
  - On Apple Silicon Macs: defaults to linux/arm64 (native performance)
  - On Intel/AMD systems: defaults to linux/amd64
  - Use --platform to override auto-detection
  - Use --multi-platform to build for both architectures

EOF
}

# Function to detect platform
detect_platform() {
    local arch
    arch=$(uname -m)
    local os
    os=$(uname -s)
    
    if [[ "$os" == "Darwin" ]]; then
        if [[ "$arch" == "arm64" ]]; then
            # Apple Silicon Mac - default to native ARM64 for best performance
            echo "linux/arm64"
            print_status "Detected Apple Silicon Mac. Using native linux/arm64 for optimal performance."
            print_status "Use --platform linux/amd64 if you need AMD64 compatibility."
        else
            echo "linux/amd64"
        fi
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        echo "linux/arm64"
    else
        echo "linux/amd64"
    fi
}

# Function to validate Docker installation
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    print_status "Docker is available and running"
}

# Function to check buildx support
check_buildx_support() {
    if ! docker buildx version &> /dev/null; then
        print_error "Docker Buildx is not available"
        print_error "Multi-platform builds require Docker Buildx"
        exit 1
    fi
    
    # Check if builder supports required platforms
    local available_platforms
    available_platforms=$(docker buildx inspect --bootstrap 2>/dev/null | grep "Platforms:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    
    if ! echo "$available_platforms" | grep -q "linux/amd64"; then
        print_error "Builder does not support linux/amd64 platform"
        exit 1
    fi
    
    if ! echo "$available_platforms" | grep -q "linux/arm64"; then
        print_error "Builder does not support linux/arm64 platform"
        exit 1
    fi
    
    print_status "Docker Buildx supports multi-platform builds"
}

# Function to prepare dependencies
prepare_dependencies() {
    print_header "Preparing Dependencies"
    
    if [[ "$CLEAN_BUILD" == true ]]; then
        print_status "Cleaning existing dependencies..."
        rm -rf "$SCRIPT_DIR/dependencies"
    fi
    
    if [[ -f "$SCRIPT_DIR/prepare_dependencies.sh" ]]; then
        print_status "Running dependency preparation script..."
        cd "$SCRIPT_DIR"
        
        if [[ "$VERBOSE" == true ]]; then
            bash prepare_dependencies.sh
        else
            bash prepare_dependencies.sh > /dev/null 2>&1
        fi
        
        print_success "Dependencies prepared successfully"
    else
        print_error "prepare_dependencies.sh not found"
        exit 1
    fi
}

# Function to verify dependencies
verify_dependencies() {
    print_status "Verifying dependencies..."
    
    local deps_dir="$SCRIPT_DIR/dependencies"
    local missing_deps=()
    
    # Check for required files
    [[ ! -f "$deps_dir/jabaws.war" ]] && missing_deps+=("jabaws.war")
    [[ ! -f "$deps_dir/config.guess" ]] && missing_deps+=("config.guess")
    [[ ! -f "$deps_dir/config.sub" ]] && missing_deps+=("config.sub")
    [[ ! -d "$deps_dir/jabaws" ]] && missing_deps+=("jabaws/ directory")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please run with --clean to re-download dependencies"
        exit 1
    fi
    
    print_success "All dependencies verified"
}

# Function to build Docker image
build_docker_image() {
    print_header "Building Docker Image"
    
    # Check for multi-platform build requirements
    if [[ "$MULTI_PLATFORM" == true ]]; then
        if [[ "$PUSH_IMAGE" != true ]]; then
            print_error "Multi-platform builds require --push option"
            print_error "This is a Docker limitation for multi-arch manifests"
            exit 1
        fi
        check_buildx_support
        return build_multiplatform_image
    fi
    
    local build_args=()
    local docker_args=()
    
    # Add platform argument
    if [[ "$PLATFORM" != "auto" ]]; then
        docker_args+=("--platform" "$PLATFORM")
        print_status "Building for platform: $PLATFORM"
    fi
    
    # Add no-cache argument
    if [[ "$NO_CACHE" == true ]]; then
        docker_args+=("--no-cache")
        print_status "Building without cache"
    fi
    
    # Add progress output
    if [[ "$VERBOSE" == true ]]; then
        docker_args+=("--progress" "plain")
    fi
    
    # Build the image
    print_status "Starting Docker build..."
    print_status "Image tag: $IMAGE_TAG"
    
    cd "$SCRIPT_DIR"
    
    if docker build "${docker_args[@]}" -t "$IMAGE_TAG" .; then
        print_success "Docker image built successfully: $IMAGE_TAG"
    else
        print_error "Docker build failed"
        exit 1
    fi
}

# Function to build multi-platform image
build_multiplatform_image() {
    print_header "Building Multi-Platform Docker Image"
    print_status "Building for platforms: linux/amd64, linux/arm64"
    print_status "Image tag: $IMAGE_TAG"
    
    local buildx_args=()
    
    # Add platforms
    buildx_args+=("--platform" "linux/amd64,linux/arm64")
    
    # Add no-cache argument
    if [[ "$NO_CACHE" == true ]]; then
        buildx_args+=("--no-cache")
        print_status "Building without cache"
    fi
    
    # Add progress output
    if [[ "$VERBOSE" == true ]]; then
        buildx_args+=("--progress" "plain")
    fi
    
    # Multi-platform builds must be pushed
    buildx_args+=("--push")
    
    cd "$SCRIPT_DIR"
    
    if docker buildx build "${buildx_args[@]}" -t "$IMAGE_TAG" .; then
        print_success "Multi-platform Docker image built and pushed successfully: $IMAGE_TAG"
        print_status "Available for both linux/amd64 and linux/arm64 platforms"
    else
        print_error "Multi-platform Docker build failed"
        exit 1
    fi
}

# Function to push image
push_image() {
    # Skip if multi-platform (already pushed)
    if [[ "$MULTI_PLATFORM" == true ]]; then
        return 0
    fi
    
    if [[ "$PUSH_IMAGE" == true ]]; then
        print_header "Pushing Docker Image"
        print_status "Pushing $IMAGE_TAG to registry..."
        
        if docker push "$IMAGE_TAG"; then
            print_success "Image pushed successfully"
        else
            print_error "Failed to push image"
            exit 1
        fi
    fi
}

# Function to show build summary
show_summary() {
    print_header "Build Summary"
    echo "  Image Tag:      $IMAGE_TAG"
    if [[ "$MULTI_PLATFORM" == true ]]; then
        echo "  Platforms:      linux/amd64, linux/arm64 (multi-platform)"
    else
        echo "  Platform:       $PLATFORM"
    fi
    echo "  Clean Build:    $CLEAN_BUILD"
    echo "  No Cache:       $NO_CACHE"
    echo "  Dependencies:   $([ "$SKIP_DEPS" == true ] && echo "Skipped" || echo "Prepared")"
    echo
    print_success "Build completed successfully!"
    echo
    
    if [[ "$MULTI_PLATFORM" == true ]]; then
        echo "Multi-platform image available. To run:"
        echo "  # On any platform (Docker will pull correct architecture)"
        echo "  docker run -p 8080:8080 $IMAGE_TAG"
    else
        echo "To run the container:"
        if [[ "$PLATFORM" == "linux/amd64" ]]; then
            echo "  docker run --platform=linux/amd64 -p 8080:8080 $IMAGE_TAG"
        elif [[ "$PLATFORM" == "linux/arm64" ]]; then
            echo "  docker run --platform=linux/arm64 -p 8080:8080 $IMAGE_TAG"
        else
            echo "  docker run -p 8080:8080 $IMAGE_TAG"
        fi
    fi
    echo
    echo "JABAWS will be available at: http://localhost:8080/jabaws"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
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
        -d|--deps-only)
            DEPS_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --push)
            PUSH_IMAGE=true
            shift
            ;;
        --multi-platform)
            MULTI_PLATFORM=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate platform
if [[ "$PLATFORM" != "auto" && "$PLATFORM" != "linux/amd64" && "$PLATFORM" != "linux/arm64" ]]; then
    print_error "Invalid platform: $PLATFORM"
    print_error "Valid platforms: auto, linux/amd64, linux/arm64"
    exit 1
fi

# Multi-platform validation
if [[ "$MULTI_PLATFORM" == true ]]; then
    if [[ "$PLATFORM" != "auto" ]]; then
        print_warning "Ignoring --platform option when --multi-platform is specified"
    fi
    if [[ "$PUSH_IMAGE" != true ]]; then
        print_error "Multi-platform builds require --push option"
        print_error "Use: ./build.sh --multi-platform --push"
        exit 1
    fi
fi

# Auto-detect platform if needed
if [[ "$PLATFORM" == "auto" && "$MULTI_PLATFORM" != true ]]; then
    PLATFORM=$(detect_platform)
    print_status "Auto-detected platform: $PLATFORM"
fi

# Main execution flow
print_header "JABAWS Docker Build Script"
echo "Starting build process..."
echo

# Check prerequisites
check_docker

# Prepare or verify dependencies
if [[ "$SKIP_DEPS" == true ]]; then
    print_status "Skipping dependency preparation as requested"
    verify_dependencies
elif [[ "$DEPS_ONLY" == true ]]; then
    prepare_dependencies
    print_success "Dependencies prepared. Exiting as requested."
    exit 0
else
    if [[ ! -d "$SCRIPT_DIR/dependencies" ]] || [[ "$CLEAN_BUILD" == true ]]; then
        prepare_dependencies
    else
        print_status "Dependencies already exist. Use --clean to re-download."
        verify_dependencies
    fi
fi

# Build Docker image
build_docker_image

# Push image if requested
push_image

# Show summary
show_summary
