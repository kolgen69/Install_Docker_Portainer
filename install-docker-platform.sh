#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/vpn-stack"
LOG_FILE="${LOG_DIR}/docker-install.log"
NETWORK_NAME="vpn-stack-net"
DEFAULT_PORTAINER_PORT="9443"
PORTAINER_CONTAINER_NAME="portainer"
PORTAINER_IMAGE="portainer/portainer-ce"
PORTAINER_CERT_DIR="/opt/portainer/certs"
PORTAINER_CERT_FILE="${PORTAINER_CERT_DIR}/portainer.crt"
PORTAINER_KEY_FILE="${PORTAINER_CERT_DIR}/portainer.key"

log() {
  local message="$1"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ -f "${LOG_FILE}" ]]; then
    echo "[${timestamp}] ${message}" | tee -a "${LOG_FILE}"
  else
    echo "[${timestamp}] ${message}"
  fi
}

run_step() {
  local description="$1"
  shift

  log "${description}"
  "$@" 2>&1 | tee -a "${LOG_FILE}"
}

docker_available() {
  command -v docker >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

init_logging() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_FILE}"
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="${2:-Y}"
  local answer

  read -r -p "${prompt} " answer
  answer="$(printf '%s' "${answer}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  answer="${answer:-${default_answer}}"

  case "${answer}" in
    Y|y) return 0 ;;
    N|n) return 1 ;;
    *)
      echo "Please answer Y or n."
      prompt_yes_no "${prompt}" "${default_answer}"
      ;;
  esac
}

prompt_install_mode() {
  local mode

  echo "Select action:"
  echo "  1) Install services"
  echo "  2) Remove services"
  read -r -p "Enter choice [1-2]: " mode

  case "${mode}" in
    1) ACTION_MODE="install" ;;
    2) ACTION_MODE="remove" ;;
    *)
      echo "Please enter 1 or 2."
      prompt_install_mode
      ;;
  esac
}

prompt_portainer_port() {
  local port

  read -r -p "Enter Portainer port (default ${DEFAULT_PORTAINER_PORT}): " port
  port="${port:-${DEFAULT_PORTAINER_PORT}}"

  if [[ ! "${port}" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
    echo "Please enter a valid TCP port between 1 and 65535."
    prompt_portainer_port
    return
  fi

  PORTAINER_PORT="${port}"
}

prompt_portainer_host() {
  local host

  read -r -p "Enter Portainer access host (IP or domain): " host
  host="$(printf '%s' "${host}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -z "${host}" ]]; then
    echo "Host cannot be empty."
    prompt_portainer_host
    return
  fi

  PORTAINER_HOST="${host}"
}

prompt_portainer_tls_mode() {
  local choice

  echo "Portainer HTTPS setup:"
  echo "  1) Self-signed certificate"
  echo "  2) Use existing domain certificate"
  read -r -p "Enter choice [1-2]: " choice

  case "${choice}" in
    1) PORTAINER_TLS_MODE="self-signed" ;;
    2) PORTAINER_TLS_MODE="domain" ;;
    *)
      echo "Please enter 1 or 2."
      prompt_portainer_tls_mode
      ;;
  esac
}

prompt_domain_cert_paths() {
  local cert key

  read -r -p "Enter full path to TLS certificate (.crt or fullchain): " cert
  read -r -p "Enter full path to TLS private key (.key): " key

  cert="$(printf '%s' "${cert}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  key="$(printf '%s' "${key}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ -z "${cert}" || -z "${key}" ]]; then
    echo "Certificate and key paths are required."
    prompt_domain_cert_paths
    return
  fi

  if [[ ! -f "${cert}" || ! -f "${key}" ]]; then
    echo "Provided certificate or key file does not exist."
    prompt_domain_cert_paths
    return
  fi

  PORTAINER_DOMAIN_CERT="${cert}"
  PORTAINER_DOMAIN_KEY="${key}"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker is already installed."
    return
  fi

  run_step "Installing Docker from official repository..." bash -c "curl -fsSL https://get.docker.com | sh"
}

enable_docker() {
  run_step "Enabling Docker service autostart..." systemctl enable docker
  run_step "Starting Docker service..." systemctl start docker
}

install_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "Docker Compose plugin is already available."
    return
  fi

  run_step "Installing Docker Compose plugin..." apt-get update
  run_step "Installing Docker Compose plugin package..." apt-get install -y docker-compose-plugin
}

remove_compose() {
  if ! dpkg -s docker-compose-plugin >/dev/null 2>&1; then
    log "Docker Compose plugin is not installed."
    return
  fi

  run_step "Removing Docker Compose plugin package..." apt-get remove -y docker-compose-plugin
}

configure_docker_security() {
  if prompt_yes_no "Add current user to docker group? (Y/n)" "Y"; then
    local target_user="${SUDO_USER:-root}"

    if id -nG "${target_user}" | grep -qw docker; then
      log "User ${target_user} is already in docker group."
      return
    fi

    run_step "Adding user ${target_user} to docker group..." usermod -aG docker "${target_user}"
    log "User ${target_user} was added to docker group. Re-login may be required."
  else
    log "Skipping docker group configuration."
  fi
}

create_network() {
  if ! docker_available; then
    log "Docker is not available. Cannot create network ${NETWORK_NAME}."
    return
  fi

  if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    log "Docker network ${NETWORK_NAME} already exists."
    return
  fi

  run_step "Creating Docker network ${NETWORK_NAME}..." docker network create "${NETWORK_NAME}"
}

remove_network() {
  if ! docker_available; then
    log "Docker is not available. Cannot remove network ${NETWORK_NAME}."
    return
  fi

  if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    log "Docker network ${NETWORK_NAME} does not exist."
    return
  fi

  run_step "Removing Docker network ${NETWORK_NAME}..." docker network rm "${NETWORK_NAME}"
}

remove_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker is not installed."
    return
  fi

  run_step "Stopping Docker service..." systemctl stop docker
  run_step "Disabling Docker service autostart..." systemctl disable docker
  run_step "Removing Docker packages..." apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  run_step "Autoremoving dependencies..." apt-get autoremove -y
}

ensure_openssl() {
  if command -v openssl >/dev/null 2>&1; then
    return
  fi

  run_step "Installing OpenSSL..." apt-get update
  run_step "Installing OpenSSL package..." apt-get install -y openssl
}

prepare_portainer_certs() {
  if [[ "${PORTAINER_TLS_MODE}" == "self-signed" ]]; then
    ensure_openssl
    mkdir -p "${PORTAINER_CERT_DIR}"
    if [[ ! -f "${PORTAINER_CERT_FILE}" || ! -f "${PORTAINER_KEY_FILE}" ]]; then
      run_step "Generating self-signed certificate for Portainer..." \
        openssl req -x509 -newkey rsa:4096 -sha256 -days 825 -nodes \
          -keyout "${PORTAINER_KEY_FILE}" \
          -out "${PORTAINER_CERT_FILE}" \
          -subj "/CN=${PORTAINER_HOST}"
    else
      log "Existing self-signed certificate found at ${PORTAINER_CERT_DIR}."
    fi
  else
    mkdir -p "${PORTAINER_CERT_DIR}"
    run_step "Copying domain certificate..." cp "${PORTAINER_DOMAIN_CERT}" "${PORTAINER_CERT_FILE}"
    run_step "Copying domain key..." cp "${PORTAINER_DOMAIN_KEY}" "${PORTAINER_KEY_FILE}"
  fi
}

install_portainer() {
  if ! docker_available; then
    log "Docker is not available. Cannot install Portainer."
    return
  fi

  prompt_portainer_port
  prompt_portainer_host
  prompt_portainer_tls_mode
  if [[ "${PORTAINER_TLS_MODE}" == "domain" ]]; then
    prompt_domain_cert_paths
  fi

  prepare_portainer_certs

  if docker ps -a --format '{{.Names}}' | grep -qx "${PORTAINER_CONTAINER_NAME}"; then
    log "Portainer container already exists. Ensuring it is running..."
    run_step "Starting existing Portainer container..." docker start "${PORTAINER_CONTAINER_NAME}"
    return
  fi

  run_step "Creating Portainer data volume..." docker volume create portainer_data
  run_step "Starting Portainer container on port ${PORTAINER_PORT}..." \
    docker run -d \
      --name "${PORTAINER_CONTAINER_NAME}" \
      --restart unless-stopped \
      -p "${PORTAINER_PORT}:9443" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      -v "${PORTAINER_CERT_DIR}:/certs" \
      --ssl \
      --sslcert /certs/portainer.crt \
      --sslkey /certs/portainer.key \
      "${PORTAINER_IMAGE}"
}

remove_portainer() {
  if ! docker_available; then
    log "Docker is not available. Cannot remove Portainer."
    return
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx "${PORTAINER_CONTAINER_NAME}"; then
    run_step "Stopping Portainer container..." docker stop "${PORTAINER_CONTAINER_NAME}"
    run_step "Removing Portainer container..." docker rm "${PORTAINER_CONTAINER_NAME}"
  else
    log "Portainer container does not exist."
  fi

  if docker volume ls --format '{{.Name}}' | grep -qx portainer_data; then
    run_step "Removing Portainer data volume..." docker volume rm portainer_data
  fi

  if [[ -d "${PORTAINER_CERT_DIR}" ]]; then
    run_step "Removing Portainer certificates..." rm -rf "${PORTAINER_CERT_DIR}"
  fi
}

print_summary() {
  local host

  host="${PORTAINER_HOST:-SERVER_IP}"

  echo
  echo "Docker installed"
  echo "Docker Compose installed"
  echo "Portainer running"
  echo "Docker platform ready"
  echo
  echo "Portainer access: https://${host}:${PORTAINER_PORT}"
  echo "Log file: ${LOG_FILE}"
}

main() {
  require_root
  init_logging

  prompt_install_mode

  if [[ "${ACTION_MODE}" == "install" ]]; then
    log "Starting Docker platform installation..."

    if prompt_yes_no "Install Docker? (Y/n)" "Y"; then
      install_docker
      enable_docker
      configure_docker_security
    else
      log "Skipping Docker installation."
    fi

    if prompt_yes_no "Install Docker Compose plugin? (Y/n)" "Y"; then
      install_compose
    else
      log "Skipping Docker Compose installation."
    fi

    if prompt_yes_no "Create Docker network ${NETWORK_NAME}? (Y/n)" "Y"; then
      create_network
    else
      log "Skipping Docker network creation."
    fi

    if prompt_yes_no "Install Portainer? (Y/n)" "Y"; then
      install_portainer
    else
      log "Skipping Portainer installation."
    fi

    log "Docker platform installation completed successfully."
    print_summary
  else
    log "Starting Docker platform removal..."

    if prompt_yes_no "Remove Portainer? (Y/n)" "Y"; then
      remove_portainer
    else
      log "Skipping Portainer removal."
    fi

    if prompt_yes_no "Remove Docker network ${NETWORK_NAME}? (Y/n)" "Y"; then
      remove_network
    else
      log "Skipping Docker network removal."
    fi

    if prompt_yes_no "Remove Docker Compose plugin? (Y/n)" "Y"; then
      remove_compose
    else
      log "Skipping Docker Compose removal."
    fi

    if prompt_yes_no "Remove Docker Engine? (Y/n)" "Y"; then
      remove_docker
    else
      log "Skipping Docker removal."
    fi

    log "Docker platform removal completed successfully."
  fi
}

PORTAINER_PORT="${DEFAULT_PORTAINER_PORT}"
PORTAINER_HOST=""
PORTAINER_TLS_MODE="self-signed"
PORTAINER_DOMAIN_CERT=""
PORTAINER_DOMAIN_KEY=""
ACTION_MODE="install"
main "$@"


