# Docker Platform Installer

This project contains an interactive installation script for the Docker platform required by the VPN stack.

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

1. Installs or removes Docker
2. Installs or removes Docker Compose plugin
3. Optionally adds the current user to the `docker` group
4. Creates or removes the Docker network `vpn-stack-net`
5. Installs or removes Portainer in a container
6. Sets up HTTPS for Portainer with a self-signed or existing domain certificate
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

- `Select action: Install services or Remove services`
- `Install Docker? (Y/n)`
- `Install Docker Compose plugin? (Y/n)`
- `Create Docker network vpn-stack-net? (Y/n)`
- `Install Portainer? (Y/n)`
- `Add current user to docker group? (Y/n)`
- `Enter Portainer port (default 9443):`
- `Enter Portainer access host (IP or domain):`
- `Portainer HTTPS setup: self-signed or existing domain certificate`
- `Enter full path to TLS certificate (.crt or fullchain):`
- `Enter full path to TLS private key (.key):`

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
- HTTPS certificates are stored in `/opt/portainer/certs`
- The admin account is created during the first login

## Logs

Installation log path:

```text
/var/log/vpn-stack/docker-install.log
```
