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

1. Create the data directory and INI files for bind mounts:
   ```bash
   mkdir -p data
   touch data/SkimSrv.ini data/UberSDRIntf.ini
   ```

2. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your station details:
   ```bash
   CALLSIGN=YOUR_CALL
   NAME=Your Name
   QTH=Your Location
   SQUARE=Your Grid Square
   UBERSDR_HOST=your_ubersdr_host
   UBERSDR_PORT=8080
   ```

4. Start the container:
   ```bash
   docker-compose up -d
   ```
   
   Or use the provided helper script:
   ```bash
   ./docker.sh up -d
   ```
   
   The helper script automatically creates the data directory and INI files if they don't exist.

5. Access the web interface:
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

## Automatic Restart Trigger

CW Skimmer supports automatic restart when configuration changes are detected. This is useful when external systems need to trigger a container restart.

### How It Works

1. An external container or process writes a trigger file: `/var/run/restart-trigger/restart-cwskimmer`
2. CW Skimmer's entrypoint script detects the file and restarts the container
3. The trigger file is automatically removed after restart

This mechanism is similar to how radiod and caddy restart when triggered by UberSDR in the ka9q_ubersdr project.

### Manual Trigger

You can manually trigger a CW Skimmer restart from within another container that shares the `restart-trigger` volume:

```bash
docker exec <other-container> touch /var/run/restart-trigger/restart-cwskimmer
```

Or from the host if you have access to the volume:

```bash
docker exec cwskimmer touch /var/run/restart-trigger/restart-cwskimmer
```

The CW Skimmer container will detect the file and restart within 0.5 seconds.

### Sharing the Restart Trigger Volume

To enable another container to trigger CW Skimmer restarts, add the `restart-trigger` volume to that container's configuration:

```yaml
services:
  another_service:
    image: some-image
    volumes:
      - restart-trigger:/var/run/restart-trigger
```

Then reference the shared volume in the volumes section:

```yaml
volumes:
  restart-trigger:
    external: true
    name: ubersdr-cwskimmer_restart-trigger
```

## Persistent Configuration

Configuration files are persisted using bind mounts to the host filesystem, allowing easy access and modification:

### INI File Bind Mounts

Two configuration files are bind-mounted from the `./data/` directory:

1. **SkimSrv.ini** - SkimSrv configuration (callsign, QTH, name, grid square)
   - **Host Path**: `./data/SkimSrv.ini`
   - **Container Path**: `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini`

2. **UberSDRIntf.ini** - UberSDR driver configuration (host, port)
   - **Host Path**: `./data/UberSDRIntf.ini`
   - **Container Path**: `/skimmersrv_1.6/app/UberSDRIntf.ini`

### Docker Compose Volume Configuration

```yaml
volumes:
  # Bind mount for INI files - preserves configuration across restarts
  - ./data/SkimSrv.ini:/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini
  - ./data/UberSDRIntf.ini:/skimmersrv_1.6/app/UberSDRIntf.ini
  # Shared volume for restart trigger
  - restart-trigger:/var/run/restart-trigger
```

### First Run Initialization

On first run, if the INI files don't exist or are empty, the startup script automatically initializes them with template values. The files are then configured with your environment variables (CALLSIGN, QTH, etc.).

### Configuration Preservation

The startup script intelligently handles configuration:
- **Empty placeholders**: Automatically filled with environment variables
- **Existing values**: Preserved across container restarts
- **User modifications**: Respected and not overwritten

This allows you to:
- Edit INI files directly on the host in `./data/`
- Modify settings through the application UI
- Change environment variables for initial setup only

### Bind Mount Benefits

1. **Easy Access**: Configuration files are directly accessible on the host filesystem
2. **Simple Backup**: Just copy the `./data/` directory
3. **Version Control**: Can track configuration changes in git (if desired)
4. **No Volume Conflicts**: Application files remain in the container image

### Restart Trigger Volume

The `restart-trigger` volume is used for coordinating container restarts:

- **Container Path**: `/var/run/restart-trigger/`
- **Volume Name**: `restart-trigger`
- **Purpose**: Allows external containers to trigger CW Skimmer restarts by creating the `restart-cwskimmer` file

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
