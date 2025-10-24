# Makefile for Airflow Docker Image Management
# Usage: make <target>

# Variables
IMAGE_NAME ?= airflow-operator
IMAGE_TAG ?= latest
REGISTRY ?= 
AIRFLOW_VERSION ?= 3.1.0
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
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: build
build: ## Build the Docker image
	@echo "$(GREEN)[INFO]$(NC) Building Airflow Docker image: $(FULL_IMAGE_NAME)"
	@echo "$(BLUE)[INFO]$(NC) Airflow version: $(AIRFLOW_VERSION)"
	@docker build --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) -t $(FULL_IMAGE_NAME) .
	@echo "$(GREEN)[INFO]$(NC) Successfully built image: $(FULL_IMAGE_NAME)"
	@docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep $(IMAGE_NAME) || true

.PHONY: build-no-cache
build-no-cache: ## Build the Docker image without cache
	@echo "$(GREEN)[INFO]$(NC) Building Airflow Docker image without cache: $(FULL_IMAGE_NAME)"
	@docker build --no-cache --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) -t $(FULL_IMAGE_NAME) .
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
run: ## Run the Airflow webserver container
	@echo "$(GREEN)[INFO]$(NC) Starting Airflow webserver..."
	@docker run --rm -p 8080:8080 $(FULL_IMAGE_NAME)

.PHONY: run-scheduler
run-scheduler: ## Run the Airflow scheduler
	@echo "$(GREEN)[INFO]$(NC) Starting Airflow scheduler..."
	@docker run --rm $(FULL_IMAGE_NAME) airflow scheduler

.PHONY: shell
shell: ## Open shell in the container
	@echo "$(GREEN)[INFO]$(NC) Opening shell in container..."
	@docker run --rm -it $(FULL_IMAGE_NAME) /bin/bash

.PHONY: test
test: ## Test the Docker image
	@echo "$(GREEN)[INFO]$(NC) Testing Airflow Docker image..."
	@docker run --rm $(FULL_IMAGE_NAME) airflow version
	@docker run --rm $(FULL_IMAGE_NAME) airflow config list
	@echo "$(GREEN)[INFO]$(NC) All tests passed!"

.PHONY: health-check
health-check: ## Check container health
	@echo "$(GREEN)[INFO]$(NC) Checking container health..."
	@docker run --rm -d --name airflow-health-test -p 8080:8080 $(FULL_IMAGE_NAME)
	@sleep 10
	@docker exec airflow-health-test curl -f http://localhost:8080/health || echo "$(RED)[ERROR]$(NC) Health check failed"
	@docker stop airflow-health-test
	@echo "$(GREEN)[INFO]$(NC) Health check completed"

.PHONY: clean
clean: ## Clean up local Docker images
	@echo "$(YELLOW)[WARNING]$(NC) Cleaning up local Docker images..."
	@docker rmi $(FULL_IMAGE_NAME) 2>/dev/null || true
	@echo "$(GREEN)[INFO]$(NC) Cleanup completed"

.PHONY: clean-all
clean-all: ## Clean up all related Docker images and containers
	@echo "$(YELLOW)[WARNING]$(NC) Cleaning up all Docker resources..."
	@docker stop $$(docker ps -q --filter ancestor=$(FULL_IMAGE_NAME)) 2>/dev/null || true
	@docker rmi $$(docker images -q $(IMAGE_NAME)) 2>/dev/null || true
	@docker system prune -f
	@echo "$(GREEN)[INFO]$(NC) Complete cleanup finished"

.PHONY: logs
logs: ## Show container logs
	@echo "$(GREEN)[INFO]$(NC) Showing container logs..."
	@docker logs $$(docker ps -q --filter ancestor=$(FULL_IMAGE_NAME)) 2>/dev/null || echo "$(RED)[ERROR]$(NC) No running containers found"

.PHONY: inspect
inspect: ## Inspect the Docker image
	@echo "$(GREEN)[INFO]$(NC) Inspecting Docker image: $(FULL_IMAGE_NAME)"
	@docker inspect $(FULL_IMAGE_NAME)

.PHONY: size
size: ## Show image size information
	@echo "$(GREEN)[INFO]$(NC) Image size information:"
	@docker images $(IMAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

.PHONY: security-scan
security-scan: ## Run security scan on the image (requires trivy)
	@echo "$(GREEN)[INFO]$(NC) Running security scan..."
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image $(FULL_IMAGE_NAME); \
	else \
		echo "$(YELLOW)[WARNING]$(NC) trivy not installed. Install with: brew install trivy"; \
	fi

# Development targets
.PHONY: dev-build
dev-build: ## Build development image with debug tools
	@echo "$(GREEN)[INFO]$(NC) Building development image..."
	@docker build --build-arg AIRFLOW_VERSION=$(AIRFLOW_VERSION) --target base -t $(IMAGE_NAME):dev .

.PHONY: dev-run
dev-run: ## Run development container with volume mounts
	@echo "$(GREEN)[INFO]$(NC) Starting development container..."
	@docker run --rm -it \
		-v $(PWD)/dags:/opt/airflow/dags \
		-v $(PWD)/plugins:/opt/airflow/plugins \
		-v $(PWD)/logs:/opt/airflow/logs \
		-p 8080:8080 \
		$(IMAGE_NAME):dev /bin/bash
