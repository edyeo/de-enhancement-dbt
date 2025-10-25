# Multi-stage build for optimized Airflow image
ARG AIRFLOW_VERSION=3.1.0
FROM apache/airflow:${AIRFLOW_VERSION} as base

# Set environment variables
ENV AIRFLOW_HOME=/opt/airflow
ENV PYTHONPATH=/opt/airflow/dags:/opt/airflow/plugins
ENV AIRFLOW__CORE__EXECUTOR=KubernetesExecutor
ENV AIRFLOW__KUBERNETES__NAMESPACE=default
ENV AIRFLOW__KUBERNETES__WORKER_CONTAINER_REPOSITORY=apache/airflow
ENV AIRFLOW__KUBERNETES__WORKER_CONTAINER_TAG=3.1.0
ENV AIRFLOW__KUBERNETES__DELETE_WORKER_PODS=True
ENV AIRFLOW__KUBERNETES__DELETE_WORKER_PODS_ON_FAILURE=True

# Switch to root for system package installation
USER root

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        vim \
        curl \
        git \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Create custom directories
RUN mkdir -p /opt/airflow/dags /opt/airflow/plugins /opt/airflow/logs \
    && chown -R airflow:airflow /opt/airflow

# Switch back to airflow user
USER airflow

# Health check for scheduler (check if scheduler process is running)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f "airflow scheduler" || exit 1

# Default command (can be overridden in Helm chart)
CMD ["airflow", "scheduler"]