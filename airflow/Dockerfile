# Multi-stage build for optimized Airflow image
ARG AIRFLOW_VERSION=3.1.0
FROM apache/airflow:${AIRFLOW_VERSION} as base


# Set environment variables
ENV AIRFLOW_HOME=/opt/airflow
ENV PYTHONPATH=/opt/airflow/dags:/opt/airflow/plugins
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

# Create custom directories
RUN mkdir -p /opt/airflow/dags /opt/airflow/plugins /opt/airflow/logs \
    && chown -R airflow:root /opt/airflow

# Switch back to airflow user
USER airflow

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

# Default command (can be overridden in Helm chart)
CMD ["airflow", "scheduler"]