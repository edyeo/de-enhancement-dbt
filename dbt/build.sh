#!/bin/bash

# Build script for dbt Docker image
set -e

# Configuration
IMAGE_NAME=${1:-"dbt-operator"}
IMAGE_TAG=${2:-"latest"}
REGISTRY=${3:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build the image
print_info "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"

if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
fi

docker build -t "$FULL_IMAGE_NAME" .

if [ $? -eq 0 ]; then
    print_info "Successfully built image: $FULL_IMAGE_NAME"
    
    # Show image size
    IMAGE_SIZE=$(docker images --format "table {{.Size}}" "$FULL_IMAGE_NAME" | tail -n 1)
    print_info "Image size: $IMAGE_SIZE"
    
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
echo "  # Run dbt deps"
echo "  docker run --rm $FULL_IMAGE_NAME dbt deps"
echo ""
echo "  # Run dbt models"
echo "  docker run --rm $FULL_IMAGE_NAME dbt run"
echo ""
echo "  # Run dbt tests"
echo "  docker run --rm $FULL_IMAGE_NAME dbt test"
echo ""
echo "  # Run with custom profiles"
echo "  docker run --rm -v \$(pwd)/profiles.yml:/root/.dbt/profiles.yml $FULL_IMAGE_NAME dbt run"

