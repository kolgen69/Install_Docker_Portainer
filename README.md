# Docker Platform Installer

This project contains an interactive installation script for the Docker & Portainer
Components installed and configured:

- Docker
- Docker Compose plugin
- Portainer
- Dedicated Docker network for VPN services

## Files

- `docker-platform-spec.md` - original specification
- `install-docker-platform.sh` - interactive installation script

## What the Script Does

The script performs the following actions:

1. Installs Docker from the official repository
2. Enables and starts the Docker service
3. Installs Docker Compose plugin
4. Optionally adds the current user to the `docker` group
5. Creates the Docker network `vpn-stack-net`
6. Installs and starts Portainer in a container
7. Writes logs to `/var/log/vpn-stack/docker-install.log`

## Requirements

- Ubuntu/Debian-based Linux system
- `root` access or `sudo`
- Internet access for package and image downloads

## How to Run

Make the script executable:

```bash
chmod +x install-docker-platform.sh
```

Run the installer as root:

```bash
sudo ./install-docker-platform.sh
```

## Interactive Prompts

During execution the script asks:

- `Add current user to docker group? (Y/n)`
- `Enter Portainer port (default 9443):`

If you accept the docker group change, re-login may be required before Docker can be used without `sudo`.

## Result

After successful installation, the script prints:

```text
Docker installed
Docker Compose installed
Portainer running
Docker platform ready
```

It also shows the Portainer access URL in this format:

```text
https://SERVER_IP:9443
```

## Portainer Notes

- Portainer runs in container `portainer`
- Portainer data is stored in Docker volume `portainer_data`
- Default HTTPS port is `9443`
- The admin account is created during the first login

## Logs

Installation log path:

```text
/var/log/vpn-stack/docker-install.log
```
