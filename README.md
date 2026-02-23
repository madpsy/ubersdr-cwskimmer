# Docker CW Skimmer

This project is based on the original work by [8cH9azbsFifZ](https://github.com/8cH9azbsFifZ/docker-cwskimmer).

## Overview

A Docker container that runs CW Skimmer Server with RBN Aggregator and UberSDR driver support. This setup allows you to operate a Reverse Beacon Network (RBN) skimmer station using the ka9q_ubersdr software-defined radio system.

## What Gets Installed

### Base System
- **Debian Bookworm** base image
- **Wine** (with 32-bit architecture support) for running Windows applications
- **XFCE4** desktop environment
- **VNC Server** (x11vnc) and **noVNC** for web-based remote access
- **Xvfb** for virtual display

### Core Applications

#### CW Skimmer
- **Version 1.9** (legacy)
- **Version 2.1** (current)
- Morse code decoding software for amateur radio

#### Skimmer Server
- **Version 1.6**
- Server component that provides telnet interface for CW Skimmer
- Configured with ka9q_ubersdr driver support

#### RBN Aggregator
- **Version 6.7**
- Aggregates and forwards CW spots to the Reverse Beacon Network
- Downloaded directly from reversebeacon.net

#### UberSDR Driver
- ka9q_ubersdr CW_Skimmer driver
- Provides interface between CW Skimmer and ka9q_ubersdr SDR software
- Downloaded from [madpsy/ka9q_ubersdr](https://github.com/madpsy/ka9q_ubersdr)

### Wine Dependencies
- **.NET Framework 4.6** (via winetricks)
- **Core fonts** and **Tahoma** font
- **GDI+** graphics library
- Font smoothing configured for RGB

### Additional Tools
- cabextract, innoextract, unzip (for extracting installers)
- wget, tar, net-tools
- dbus-x11, xdotool
- supervisor (for process management)
- fonts-liberation, fonts-dejavu-core

## Environment Variables

### Station Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CALLSIGN` | `MM3NDH` | Your amateur radio callsign |
| `NAME` | `Nathan` | Operator name |
| `QTH` | `Dalgety Bay` | Station location (city/town) |
| `SQUARE` | `IO86ha` | Maidenhead grid square locator |

### UberSDR Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `UBERSDR_HOST` | `ka9q_ubersdr` | Hostname or IP of the ka9q_ubersdr server |
| `UBERSDR_PORT` | `8080` | Port number for ka9q_ubersdr connection |

### Internal Configuration Paths

These are set automatically and typically don't need to be changed:

| Variable | Value | Description |
|----------|-------|-------------|
| `PATH_INI_SKIMSRV` | `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini` | SkimSrv configuration file |
| `PATH_INI_AGGREGATOR` | `/rbnaggregator_6.7/Aggregator.ini` | RBN Aggregator configuration file |
| `PATH_INI_UBERSDR` | `/skimmersrv_1.6/app/UberSDRIntf.ini` | UberSDR driver configuration file |
| `LOGFILE_UBERSDR` | `/root/ubersdr_driver_log_file.txt` | UberSDR driver log file |
| `LOGIFLE_AGGREGATOR` | `/root/AggregatorLog.txt` | RBN Aggregator log file |

### Display Configuration

| Variable | Value | Description |
|----------|-------|-------------|
| `DISPLAY` | `:0` | X11 display number |
| `HOME` | `/root` | Home directory |
| `LC_ALL` | `C.UTF-8` | Locale setting |
| `LANG` | `en_US.UTF-8` | Language setting |

## Exposed Ports

| Port | Service | Description |
|------|---------|-------------|
| `7373` | noVNC | Web-based VNC interface for remote desktop access |
| `7300` | SkimSrv | Telnet server for CW Skimmer control |
| `7550` | RBN Aggregator | RBN Aggregator service port |

## Usage

### Using Docker Compose (Recommended)

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your station details:
   ```bash
   CALLSIGN=YOUR_CALL
   NAME=Your Name
   QTH=Your Location
   SQUARE=Your Grid Square
   UBERSDR_HOST=your_ubersdr_host
   UBERSDR_PORT=8080
   ```

3. Start the container:
   ```bash
   docker-compose up -d
   ```

4. Access the web interface:
   - Open your browser to `http://localhost:7373`
   - You'll see the XFCE desktop with CW Skimmer running

### Using Docker Run

```bash
docker run -d \
  --name cwskimmer \
  --privileged \
  -e CALLSIGN=YOUR_CALL \
  -e NAME="Your Name" \
  -e QTH="Your Location" \
  -e SQUARE=YOUR_GRID \
  -e UBERSDR_HOST=ka9q_ubersdr \
  -e UBERSDR_PORT=8080 \
  -p 7373:7373 \
  -p 7300:7300 \
  -p 7550:7550 \
  madpsy/ubersdr-cwskimmer:latest
```

## SkimSrv Persistent Volumes

Two persistent Docker volumes have been configured for SkimSrv that can be shared between containers:

1. **skimsrv** - SkimSrv application directory (contains `UberSDRIntf.ini`)
2. **skimsrv_config** - SkimSrv configuration directory (contains `SkimSrv.ini`)

### Volume Configuration Details

#### Volume 1: skimsrv
- **Container Path**: `/skimmersrv_1.6/app/`
- **Volume Name**: `skimsrv`
- **Contains**: `UberSDRIntf.ini` and application files

#### Volume 2: skimsrv_config
- **Container Path**: `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/`
- **Volume Name**: `skimsrv_config`
- **Contains**: `SkimSrv.ini` and user configuration

### Docker Compose Volume Configuration

The volumes are defined in the `docker-compose.yml` file:

```yaml
volumes:
  # Persistent volume for SkimSrv application
  - skimsrv:/skimmersrv_1.6/app
  # Persistent volume for SkimSrv configuration
  - skimsrv_config:/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv

# Named volumes for persistent storage
volumes:
  skimsrv:
    driver: local
  skimsrv_config:
    driver: local
```

### Volume Benefits

1. **Persistence**: Configuration survives container restarts and removals
2. **Shareability**: Other containers can mount the same volume to access the configuration
3. **Backup**: Easy to backup and restore using Docker volume commands

### Sharing Volumes with Other Containers

To share these volumes with another container, add them to that container's configuration:

```yaml
services:
  another_service:
    image: some-image
    volumes:
      - skimsrv:/path/in/container:ro          # :ro for read-only access
      - skimsrv_config:/another/path:ro
```

### Managing the Volumes

**View volume details:**
```bash
docker volume inspect skimsrv
docker volume inspect skimsrv_config
```

**Backup volumes:**
```bash
# Backup skimsrv
docker run --rm -v skimsrv:/data -v $(pwd):/backup alpine tar czf /backup/skimsrv_backup.tar.gz -C /data .

# Backup skimsrv_config
docker run --rm -v skimsrv_config:/data -v $(pwd):/backup alpine tar czf /backup/skimsrv_config_backup.tar.gz -C /data .
```

**Restore volumes:**
```bash
# Restore skimsrv
docker run --rm -v skimsrv:/data -v $(pwd):/backup alpine tar xzf /backup/skimsrv_backup.tar.gz -C /data

# Restore skimsrv_config
docker run --rm -v skimsrv_config:/data -v $(pwd):/backup alpine tar xzf /backup/skimsrv_config_backup.tar.gz -C /data
```

**Remove volumes** (when not in use):
```bash
docker volume rm skimsrv skimsrv_config
```

## Configuration Files

The container includes pre-configured templates for:
- **SkimSrv.ini** - Skimmer Server configuration
- **Aggregator.ini** - RBN Aggregator configuration
- **UberSDRIntf.ini** - UberSDR driver settings

### UberSDRIntf.ini
Automatically configured at container startup with:
- **Host**: Set via `UBERSDR_HOST` environment variable (default: `ka9q_ubersdr`)
- **Port**: Set via `UBERSDR_PORT` environment variable (default: `8080`)

### SkimSrv.ini
Automatically configured at container startup with:
- **Call**: Set via `CALLSIGN` environment variable (default: `MM3NDH`)
- **QTH**: Set via `QTH` environment variable (default: `Dalgety Bay`)
- **Name**: Set via `NAME` environment variable (default: `Nathan`)
- **Square**: Set via `SQUARE` environment variable (default: `IO86ha`)

These values are configured in the startup script at `/bin/startup.sh`.

## Startup Process

The [`startup.sh`](config/startup.sh) script performs the following:

1. Configures SkimSrv with your callsign, QTH, name, and grid square
2. Configures RBN Aggregator with your callsign
3. Configures UberSDR driver with the specified host and port
4. Updates supervisor configuration with correct version numbers
5. Creates and tails log files for monitoring
6. Launches supervisord to manage all services

## Building from Source

```bash
docker build -t cwskimmer .
```

Note: You'll need the installation files in the `install/` directory:
- `install/Skimmer_1.9/CwSkimmer.zip`
- `install/Skimmer_2.1/CwSkimmer.zip`
- `install/SkimmerSrv_1.6/SkimSrv.zip`
- `install/patt3ch/patt3ch.lst`

## Requirements

- Docker Engine 20.10 or later
- Docker Compose 1.29 or later (if using docker-compose)
- Access to a ka9q_ubersdr server instance
- Valid amateur radio license and callsign

## Troubleshooting

### Viewing Logs

```bash
docker logs cwskimmer
```

### Accessing the Container Shell

```bash
docker exec -it cwskimmer bash
```

### Checking Configuration Files

The configuration files are located at:
- SkimSrv: `$PATH_INI_SKIMSRV`
- Aggregator: `$PATH_INI_AGGREGATOR`
- UberSDR: `$PATH_INI_UBERSDR`

## Notes

- Both volumes are created automatically when you first run `docker-compose up`
- Configurations are modified at startup based on environment variables
- Entire directories are persisted, not just the INI files
- This ensures all related application and configuration files are preserved across container restarts

## License

Please refer to the original repository for licensing information.

## Credits

- Original Docker implementation: [8cH9azbsFifZ/docker-cwskimmer](https://github.com/8cH9azbsFifZ/docker-cwskimmer)
- CW Skimmer: Afreet Software
- RBN Aggregator: Reverse Beacon Network
- ka9q_ubersdr driver: [madpsy/ka9q_ubersdr](https://github.com/madpsy/ka9q_ubersdr)
