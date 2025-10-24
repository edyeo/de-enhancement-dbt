# Makefile for dbt Docker Operator
# Usage: make <target>

# Variables
IMAGE_NAME ?= dbt-operator
IMAGE_TAG ?= latest
REGISTRY ?= 
FULL_IMAGE_NAME = $(if $(REGISTRY),$(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG),$(IMAGE_NAME):$(IMAGE_TAG))

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Default target
.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the Docker image
	@echo "$(GREEN)[INFO]$(NC) Building Docker image: $(FULL_IMAGE_NAME)"
	@docker build -t $(FULL_IMAGE_NAME) .
	@echo "$(GREEN)[INFO]$(NC) Successfully built image: $(FULL_IMAGE_NAME)"
	@docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep $(IMAGE_NAME) || true

.PHONY: build-no-cache
build-no-cache: ## Build the Docker image without cache
	@echo "$(GREEN)[INFO]$(NC) Building Docker image without cache: $(FULL_IMAGE_NAME)"
	@docker build --no-cache -t $(FULL_IMAGE_NAME) .
	@echo "$(GREEN)[INFO]$(NC) Successfully built image: $(FULL_IMAGE_NAME)"

.PHONY: push
push: ## Push the Docker image to registry
	@if [ -z "$(REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) REGISTRY variable is required for push. Usage: make push REGISTRY=your-registry"; \
		exit 1; \
	fi
	@echo "$(GREEN)[INFO]$(NC) Pushing image to registry: $(FULL_IMAGE_NAME)"
	@docker push $(FULL_IMAGE_NAME)
	@echo "$(GREEN)[INFO]$(NC) Successfully pushed image to registry"

.PHONY: pull
pull: ## Pull the Docker image from registry
	@if [ -z "$(REGISTRY)" ]; then \
		echo "$(RED)[ERROR]$(NC) REGISTRY variable is required for pull. Usage: make pull REGISTRY=your-registry"; \
		exit 1; \
	fi
	@echo "$(GREEN)[INFO]$(NC) Pulling image from registry: $(FULL_IMAGE_NAME)"
	@docker pull $(FULL_IMAGE_NAME)
	@echo "$(GREEN)[INFO]$(NC) Successfully pulled image from registry"

.PHONY: run
run: ## Run the Docker container with dbt help
	@echo "$(GREEN)[INFO]$(NC) Running container: $(FULL_IMAGE_NAME)"
	@docker run --rm $(FULL_IMAGE_NAME) poetry run dbt --help

.PHONY: run-deps
run-deps: ## Run dbt deps in the container
	@echo "$(GREEN)[INFO]$(NC) Running dbt deps in container: $(FULL_IMAGE_NAME)"
	@docker run --rm $(FULL_IMAGE_NAME) poetry run dbt deps

.PHONY: run-test
run-test: ## Run dbt test in the container
	@echo "$(GREEN)[INFO]$(NC) Running dbt test in container: $(FULL_IMAGE_NAME)"
	@docker run --rm $(FULL_IMAGE_NAME) poetry run dbt test

.PHONY: run-compile
run-compile: ## Run dbt compile in the container
	@echo "$(GREEN)[INFO]$(NC) Running dbt compile in container: $(FULL_IMAGE_NAME)"
	@docker run --rm $(FULL_IMAGE_NAME) poetry run dbt compile

.PHONY: shell
shell: ## Open shell in the Docker container
	@echo "$(GREEN)[INFO]$(NC) Opening shell in container: $(FULL_IMAGE_NAME)"
	@docker run --rm -it $(FULL_IMAGE_NAME) /bin/bash

.PHONY: clean
clean: ## Remove the Docker image
	@echo "$(YELLOW)[WARNING]$(NC) Removing Docker image: $(FULL_IMAGE_NAME)"
	@docker rmi $(FULL_IMAGE_NAME) || true
	@echo "$(GREEN)[INFO]$(NC) Image removed successfully"

.PHONY: clean-all
clean-all: ## Remove all dbt-operator images
	@echo "$(YELLOW)[WARNING]$(NC) Removing all dbt-operator images"
	@docker images | grep $(IMAGE_NAME) | awk '{print $$3}' | xargs -r docker rmi || true
	@echo "$(GREEN)[INFO]$(NC) All dbt-operator images removed"

.PHONY: inspect
inspect: ## Inspect the Docker image
	@echo "$(GREEN)[INFO]$(NC) Inspecting image: $(FULL_IMAGE_NAME)"
	@docker inspect $(FULL_IMAGE_NAME)

.PHONY: size
size: ## Show Docker image size
	@echo "$(GREEN)[INFO]$(NC) Image size information:"
	@docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep $(IMAGE_NAME) || echo "No images found"

.PHONY: test
test: build ## Build and test the Docker image
	@echo "$(GREEN)[INFO]$(NC) Testing Docker image: $(FULL_IMAGE_NAME)"
	@echo "$(BLUE)[TEST]$(NC) Testing dbt version..."
	@docker run --rm $(FULL_IMAGE_NAME) dbt --version
	@echo "$(BLUE)[TEST]$(NC) Testing dbt help..."
	@docker run --rm $(FULL_IMAGE_NAME) dbt --help
	@echo "$(GREEN)[INFO]$(NC) All tests passed!"

.PHONY: dev
dev: ## Build and run in development mode with volume mount
	@echo "$(GREEN)[INFO]$(NC) Running in development mode with volume mount"
	@docker run --rm -it -v $(PWD):/app $(FULL_IMAGE_NAME) /bin/bash

# Airflow Kubernetes Pod Operator examples
.PHONY: airflow-examples
airflow-examples: ## Show Airflow Kubernetes Pod Operator usage examples
	@echo "$(GREEN)[INFO]$(NC) Airflow Kubernetes Pod Operator Examples:"
	@echo ""
	@echo "$(BLUE)Basic dbt run task:$(NC)"
	@echo "from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator"
	@echo ""
	@echo "dbt_run_task = KubernetesPodOperator("
	@echo "    task_id='dbt_run',"
	@echo "    name='dbt-run',"
	@echo "    image='$(FULL_IMAGE_NAME)',"
	@echo "    cmds=['dbt'],"
	@echo "    arguments=['run'],"
	@echo "    namespace='default',"
	@echo "    is_delete_operator_pod=True,"
	@echo "    get_logs=True,"
	@echo ")"
	@echo ""
	@echo "$(BLUE)dbt test task with environment variables:$(NC)"
	@echo "dbt_test_task = KubernetesPodOperator("
	@echo "    task_id='dbt_test',"
	@echo "    name='dbt-test',"
	@echo "    image='$(FULL_IMAGE_NAME)',"
	@echo "    cmds=['dbt'],"
	@echo "    arguments=['test'],"
	@echo "    namespace='default',"
	@echo "    env_vars={"
	@echo "        'DBT_HOST': 'your-db-host',"
	@echo "        'DBT_USER': 'your-db-user',"
	@echo "        'DBT_PASSWORD': 'your-db-password',"
	@echo "        'DBT_DATABASE': 'your-database',"
	@echo "        'DBT_SCHEMA': 'your-schema'"
	@echo "    },"
	@echo "    is_delete_operator_pod=True,"
	@echo "    get_logs=True,"
	@echo ")"

# Check if Docker is running
.PHONY: check-docker
check-docker:
	@if ! docker info > /dev/null 2>&1; then \
		echo "$(RED)[ERROR]$(NC) Docker is not running. Please start Docker and try again."; \
		exit 1; \
	fi

# Poetry commands
.PHONY: poetry-install
poetry-install: ## Install Poetry dependencies locally
	@echo "$(GREEN)[INFO]$(NC) Installing Poetry dependencies..."
	@poetry install
	@echo "$(GREEN)[INFO]$(NC) Dependencies installed successfully"

.PHONY: poetry-shell
poetry-shell: ## Activate Poetry shell
	@echo "$(GREEN)[INFO]$(NC) Activating Poetry shell..."
	@poetry shell

.PHONY: poetry-update
poetry-update: ## Update Poetry dependencies
	@echo "$(GREEN)[INFO]$(NC) Updating Poetry dependencies..."
	@poetry update
	@echo "$(GREEN)[INFO]$(NC) Dependencies updated successfully"

.PHONY: poetry-lock
poetry-lock: ## Generate poetry.lock file
	@echo "$(GREEN)[INFO]$(NC) Generating poetry.lock..."
	@poetry lock
	@echo "$(GREEN)[INFO]$(NC) poetry.lock generated successfully"

.PHONY: poetry-check
poetry-check: ## Check Poetry configuration
	@echo "$(GREEN)[INFO]$(NC) Checking Poetry configuration..."
	@poetry check
	@poetry env info

.PHONY: poetry-clean
poetry-clean: ## Clean Poetry cache and virtual environment
	@echo "$(YELLOW)[WARNING]$(NC) Cleaning Poetry cache and virtual environment..."
	@poetry cache clear --all pypi
	@rm -rf .venv
	@echo "$(GREEN)[INFO]$(NC) Poetry environment cleaned"

# Ensure Docker is running before any Docker operations
build build-no-cache push pull run run-deps run-test run-compile shell clean clean-all inspect size test dev: check-docker
