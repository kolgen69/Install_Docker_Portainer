#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/vpn-stack"
LOG_FILE="${LOG_DIR}/docker-install.log"
DEFAULT_PORTAINER_PORT="9443"
PORTAINER_CONTAINER_NAME="portainer"
PORTAINER_IMAGE="portainer/portainer-ce"

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

install_portainer() {
  prompt_portainer_port

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
      "${PORTAINER_IMAGE}"
}

print_summary() {
  local server_ip

  server_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  server_ip="${server_ip:-SERVER_IP}"

  echo
  echo "Docker installed"
  echo "Docker Compose installed"
  echo "Portainer running"
  echo "Docker platform ready"
  echo "Service networks will be created by stack installers"
  echo
  echo "Portainer access: https://${server_ip}:${PORTAINER_PORT}"
  echo "Log file: ${LOG_FILE}"
}

main() {
  require_root
  init_logging

  log "Starting Docker platform installation..."

  install_docker
  enable_docker
  install_compose
  configure_docker_security
  install_portainer

  log "Docker platform installation completed successfully."
  print_summary
}

PORTAINER_PORT="${DEFAULT_PORTAINER_PORT}"
main "$@"
