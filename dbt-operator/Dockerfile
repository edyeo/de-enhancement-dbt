# Use Python 3.11 slim image as base
FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VENV_IN_PROJECT=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

# Set working directory
WORKDIR /app

# Install system dependencies including Poetry
RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    && pip install poetry==1.7.1 \
    && rm -rf /var/lib/apt/lists/*

# Copy Poetry configuration files
COPY pyproject.toml poetry.lock* ./

# Configure Poetry and install dependencies
RUN poetry config virtualenvs.in-project true && \
    poetry install --only=main --no-root && \
    rm -rf $POETRY_CACHE_DIR

# Copy dbt project files
COPY dbt_project.yml .
COPY models/ models/
COPY macros/ macros/
COPY tests/ tests/
COPY seeds/ seeds/
COPY snapshots/ snapshots/
COPY analysis/ analysis/
COPY packages.yml packages.yml

# Create dbt profiles directory
RUN mkdir -p /root/.dbt

# Copy profiles.yml template (will be mounted or configured at runtime)
COPY profiles.yml /root/.dbt/profiles.yml

# Create entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Default command
CMD ["dbt", "--help"]
