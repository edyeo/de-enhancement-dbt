#!/bin/bash

# Build script for Airflow Docker image
set -e

# Configuration
IMAGE_NAME=${1:-"airflow-operator"}
IMAGE_TAG=${2:-"latest"}
REGISTRY=${3:-""}
AIRFLOW_VERSION=${4:-"3.1.0"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Validate Airflow version
if [[ ! "$AIRFLOW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_error "Invalid Airflow version format. Expected format: X.Y.Z (e.g., 3.1.0)"
    exit 1
fi

# Build the image
print_info "Building Airflow Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
print_debug "Airflow version: ${AIRFLOW_VERSION}"
print_debug "Registry: ${REGISTRY:-'local'}"

if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
fi

# Build with build args
docker build \
    --build-arg AIRFLOW_VERSION="${AIRFLOW_VERSION}" \
    --tag "$FULL_IMAGE_NAME" \
    .

if [ $? -eq 0 ]; then
    print_info "Successfully built image: $FULL_IMAGE_NAME"
    
    # Show image size
    IMAGE_SIZE=$(docker images --format "table {{.Size}}" "$FULL_IMAGE_NAME" | tail -n 1)
    print_info "Image size: $IMAGE_SIZE"
    
    # Run basic tests
    print_info "Running basic tests..."
    
    # Test 1: Check Airflow version
    AIRFLOW_VER_OUTPUT=$(docker run --rm "$FULL_IMAGE_NAME" airflow version 2>/dev/null)
    if echo "$AIRFLOW_VER_OUTPUT" | grep -q "$AIRFLOW_VERSION"; then
        print_info "✓ Airflow version test passed"
    else
        print_warning "⚠ Airflow version test failed"
    fi
    
    # Test 2: Check if Airflow config is accessible
    if docker run --rm "$FULL_IMAGE_NAME" airflow config list > /dev/null 2>&1; then
        print_info "✓ Airflow config test passed"
    else
        print_warning "⚠ Airflow config test failed"
    fi
    
    # Test 3: Check if required directories exist
    if docker run --rm "$FULL_IMAGE_NAME" test -d /opt/airflow/dags && \
       docker run --rm "$FULL_IMAGE_NAME" test -d /opt/airflow/plugins; then
        print_info "✓ Directory structure test passed"
    else
        print_warning "⚠ Directory structure test failed"
    fi
    
    # Optional: Push to registry
    if [ -n "$REGISTRY" ]; then
        read -p "Do you want to push the image to registry? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Pushing image to registry..."
            docker push "$FULL_IMAGE_NAME"
            if [ $? -eq 0 ]; then
                print_info "Successfully pushed image to registry"
            else
                print_error "Failed to push image to registry"
                exit 1
            fi
        fi
    fi
else
    print_error "Failed to build Docker image"
    exit 1
fi

print_info "Build completed successfully!"
echo ""
echo "Usage examples:"
echo "  # Run Airflow webserver"
echo "  docker run --rm -p 8080:8080 $FULL_IMAGE_NAME"
echo ""
echo "  # Run Airflow scheduler"
echo "  docker run --rm $FULL_IMAGE_NAME airflow scheduler"
echo ""
echo "  # Run Airflow CLI commands"
echo "  docker run --rm $FULL_IMAGE_NAME airflow dags list"
echo ""
echo "  # Open shell in container"
echo "  docker run --rm -it $FULL_IMAGE_NAME /bin/bash"
echo ""
echo "Image details:"
echo "  Name: $FULL_IMAGE_NAME"
echo "  Airflow Version: $AIRFLOW_VERSION"
echo "  Size: $IMAGE_SIZE"
