#!/bin/bash

# dbt Docker Container Entrypoint Script
set -e

# Function to print colored output
print_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

# Check if dbt command is provided
if [ $# -eq 0 ]; then
    print_info "No command provided. Available dbt commands:"
    echo "  dbt run"
    echo "  dbt test"
    echo "  dbt seed"
    echo "  dbt snapshot"
    echo "  dbt compile"
    echo "  dbt parse"
    echo "  dbt docs generate"
    echo "  dbt deps"
    echo ""
    echo "Usage: docker run <image> dbt <command> [options]"
    exit 1
fi

# Change to working directory
cd /app

# Check if profiles.yml exists
if [ ! -f "/root/.dbt/profiles.yml" ]; then
    print_error "profiles.yml not found in /root/.dbt/"
    print_info "Make sure to mount or configure profiles.yml"
    exit 1
fi

# Check if dbt_project.yml exists
if [ ! -f "dbt_project.yml" ]; then
    print_error "dbt_project.yml not found in current directory"
    exit 1
fi

# Install dbt dependencies if packages.yml exists
if [ -f "packages.yml" ]; then
    print_info "Installing dbt packages..."
    poetry run dbt deps
fi

# Execute the dbt command using Poetry
print_info "Executing: poetry run dbt $*"
exec poetry run dbt "$@"
