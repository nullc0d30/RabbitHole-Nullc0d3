#!/bin/bash
# ==============================================================================
# RABBITHOLE - Docker Management Module
# ==============================================================================
# Handles Docker Compose stack deployment for Threat Intelligence platforms
# (OpenCTI, MISP) and provides utility functions for Docker operations.
# ==============================================================================

RABBIT_DOCKER_COMPOSE_DIR="${RABBIT_DOCKER_COMPOSE_DIR:-/opt/rabbithole/infra/threat-intel}"

# ------------------------------------------------------------------------------
# Check Docker availability and compose support
# ------------------------------------------------------------------------------
docker_check_available() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is required but not available. Please install Docker first."
    fi

    if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
        log_error "Docker Compose is required but not available."
    fi

    log_debug "Docker available: $(docker --version 2>/dev/null | head -1)"
    return 0
}

# ------------------------------------------------------------------------------
# Determine compose command
# ------------------------------------------------------------------------------
docker_compose_cmd() {
    if docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# ------------------------------------------------------------------------------
# Deploy the full Threat Intelligence Docker Compose stack
# ------------------------------------------------------------------------------
docker_deploy_threat_stack() {
    log_info "Initiating Threat Intelligence Infrastructure Deployment..."

    docker_check_available

    local stack_dir="${RABBIT_DOCKER_COMPOSE_DIR}"
    mkdir -p "${stack_dir}"

    # Generate secure credentials
    generate_secure_env "${stack_dir}"

    log_task "Writing Docker Compose manifest..."
    cat > "${stack_dir}/docker-compose.yml" << 'DOCKERCOMPOSE'
version: '3.8'

profiles:
  - misp
  - opencti

services:
  # --------------------------------------------------------------------------
  # OPENCTI STACK (Profile: opencti)
  # --------------------------------------------------------------------------
  redis:
    image: redis:7.2.4
    restart: always
    profiles: ["opencti"]
    volumes:
      - redis_data:/data

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.3
    volumes:
      - es_data:/usr/share/elasticsearch/data
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    restart: always
    profiles: ["opencti"]

  minio:
    image: minio/minio:RELEASE.2024-01-13T21-38-02Z
    volumes:
      - minio_data:/data
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
    command: server /data
    restart: always
    profiles: ["opencti"]

  rabbitmq:
    image: rabbitmq:3.12-management
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_DEFAULT_PASS}
    restart: always
    profiles: ["opencti"]

  opencti:
    image: opencti/platform:6.1.4
    environment:
      - NODE_OPTIONS=--max-old-space-size=8096
      - APP__ADMIN__EMAIL=${OPENCTI_ADMIN_EMAIL}
      - APP__ADMIN__PASSWORD=${OPENCTI_ADMIN_PASSWORD}
      - APP__ADMIN__TOKEN=${OPENCTI_ADMIN_TOKEN}
      - REDIS__HOSTNAME=redis
      - REDIS__PORT=6379
      - ELASTICSEARCH__URL=http://elasticsearch:9200
      - ELASTICSEARCH__USERNAME=elastic
      - ELASTICSEARCH__PASSWORD=${ELASTIC_PASSWORD}
      - MINIO__ENDPOINT=minio
      - MINIO__PORT=9000
      - MINIO__USE_SSL=false
      - MINIO__ACCESS_KEY=${MINIO_ROOT_USER}
      - MINIO__SECRET_KEY=${MINIO_ROOT_PASSWORD}
      - RABBITMQ__HOSTNAME=rabbitmq
      - RABBITMQ__PORT=5672
      - RABBITMQ__PORT_MANAGEMENT=15672
      - RABBITMQ__MANAGEMENT_SSL=false
      - RABBITMQ__USERNAME=${RABBITMQ_DEFAULT_USER}
      - RABBITMQ__PASSWORD=${RABBITMQ_DEFAULT_PASS}
    ports:
      - "8080:8080"
    depends_on:
      - redis
      - elasticsearch
      - minio
      - rabbitmq
    restart: always
    profiles: ["opencti"]

  # --------------------------------------------------------------------------
  # MISP STACK (Profile: misp)
  # --------------------------------------------------------------------------
  misp-db:
    image: mysql:8.0
    restart: always
    environment:
      - MYSQL_DATABASE=misp
      - MYSQL_USER=misp
      - MYSQL_PASSWORD=${MISP_MYSQL_PASSWORD}
      - MYSQL_ROOT_PASSWORD=${MISP_MYSQL_PASSWORD}
    volumes:
      - misp_db:/var/lib/mysql
    profiles: ["misp"]

  misp-core:
    image: ghcr.io/misp/misp-docker/misp-core:latest
    restart: always
    depends_on:
      - misp-db
    environment:
      - MYSQL_HOST=misp-db
      - MYSQL_USER=misp
      - MYSQL_PASSWORD=${MISP_MYSQL_PASSWORD}
      - MISP_BASEURL=http://localhost:8443
      - MISP_ADMIN_EMAIL=admin@admin.test
      - MISP_ADMIN_PASSPHRASE=${MISP_ADMIN_PASSPHRASE}
    ports:
      - "8443:443"
      - "8081:80"
    volumes:
      - misp_web:/var/www/MISP
    profiles: ["misp"]

volumes:
  es_data:
  minio_data:
  redis_data:
  rabbitmq_data:
  misp_db:
  misp_web:
DOCKERCOMPOSE

    log_ok "Docker Compose stack generated at ${stack_dir}"
    log_info "To launch OpenCTI:   cd ${stack_dir} && docker compose --profile opencti up -d"
    log_info "To launch MISP:      cd ${stack_dir} && docker compose --profile misp up -d"
    log_info "To launch ALL:       cd ${stack_dir} && docker compose --profile misp --profile opencti up -d"

    # Optional auto-launch
    local launch
    read -p "Do you want to launch the FULL stack now? (y/N): " launch
    if [[ "${launch}" =~ ^[Yy]$ ]]; then
        log_task "Starting services (this may take a while)..."
        cd "${stack_dir}" || log_error "Cannot access ${stack_dir}"
        docker compose --profile misp --profile opencti up -d || log_warn "Docker Compose encountered issues."
        log_ok "Services started."
    fi
}

# ------------------------------------------------------------------------------
# Stop and remove Docker stack resources
# ------------------------------------------------------------------------------
docker_teardown_stack() {
    local stack_dir="${RABBIT_DOCKER_COMPOSE_DIR}"

    if [[ ! -f "${stack_dir}/docker-compose.yml" ]]; then
        log_warn "No Docker Compose file found at ${stack_dir}"
        return 1
    fi

    log_task "Tearing down Docker stack..."
    cd "${stack_dir}" || return 1
    docker compose --profile misp --profile opencti down -v 2>> "${RABBIT_LOG_FILE}" || \
    log_warn "Docker teardown encountered issues."
    log_ok "Docker stack removed."
}

# ------------------------------------------------------------------------------
# Check Docker stack status
# ------------------------------------------------------------------------------
docker_stack_status() {
    local stack_dir="${RABBIT_DOCKER_COMPOSE_DIR}"

    if [[ ! -f "${stack_dir}/docker-compose.yml" ]]; then
        echo "not-deployed"
        return 1
    fi

    cd "${stack_dir}" || return 1
    docker compose ps --format json 2>/dev/null || echo "stopped"
}





