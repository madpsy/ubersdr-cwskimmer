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

### Band Selection (192 kHz Mode)

Control which amateur radio bands CW Skimmer monitors. Set each to `true` or `false`:

| Variable | Default | Center Freq | Band | Description |
|----------|---------|-------------|------|-------------|
| `BAND_160M` | `false` | 1.891 MHz | 160m | Top band (often noisy) |
| `BAND_80M` | `true` | 3.591 MHz | 80m | 80 meter band |
| `BAND_60M` | `true` | 5.355 MHz | 60m | 60 meter band |
| `BAND_40M` | `true` | 7.091 MHz | 40m | 40 meter band |
| `BAND_30M` | `true` | 10.191 MHz | 30m | 30 meter band (WARC) |
| `BAND_20M` | `true` | 14.091 MHz | 20m | 20 meter band |
| `BAND_17M` | `true` | 18.159 MHz | 17m | 17 meter band (WARC) |
| `BAND_15M` | `true` | 15.091 MHz | 15m | 15 meter band |
| `BAND_12M` | `true` | 24.981 MHz | 12m | 12 meter band (WARC) |
| `BAND_10M` | `true` | 28.091 MHz | 10m | 10 meter band |

**Note**: The center frequencies and CW segments are automatically configured. These settings only control which bands are enabled/disabled.

### Internal Configuration Paths

These are set automatically and typically don't need to be changed:

| Variable | Value | Description |
|----------|-------|-------------|
| `PATH_INI_SKIMSRV` | `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini` | SkimSrv instance 1 configuration file |
| `PATH_INI_SKIMSRV_2` | `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv-2/SkimSrv-2.ini` | SkimSrv instance 2 configuration file |
| `PATH_INI_AGGREGATOR` | `/rbnaggregator_6.7/Aggregator.ini` | RBN Aggregator configuration file |
| `PATH_INI_UBERSDR` | `/skimmersrv_1.6/app/UberSDRIntf.ini` | UberSDR driver instance 1 configuration file |
| `PATH_INI_UBERSDR_2` | `/skimmersrv_1.6-2/app/UberSDRIntf.ini` | UberSDR driver instance 2 configuration file |
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
| `7300` | SkimSrv Instance 1 | Telnet server for CW Skimmer instance 1 |
| `7301` | SkimSrv Instance 2 | Telnet server for CW Skimmer instance 2 |
| `7550` | RBN Aggregator | RBN Aggregator service port |

## Docker Network Configuration

This container joins the `ubersdr_sdr-network` created by the ka9q_ubersdr stack. This allows:

- **Direct container-to-container communication** with ka9q_ubersdr
- **Use container names as hostnames** (e.g., `UBERSDR_HOST=ka9q_ubersdr`)
- **No need to expose UberSDR ports** to the host
- **Better isolation** and security

### Network Requirements

The ka9q_ubersdr stack must be running first to create the `ubersdr_sdr-network`. If you get a network error when starting cwskimmer, ensure:

1. The ka9q_ubersdr stack is running: `cd /path/to/ka9q_ubersdr/docker && docker compose up -d`
2. The network exists: `docker network ls | grep sdr`
3. The network name matches: `ubersdr_sdr-network` (or adjust in [`docker-compose.yml`](docker-compose.yml))

## Usage

### Quick Start (Recommended)

Use the provided start script which handles all setup automatically:

```bash
./start.sh
```

On first run, it will:
1. Create the data directory and INI files
2. Copy `.env.example` to `.env`
3. Prompt you to edit `.env` with your configuration

After editing `.env`, run `./start.sh` again to start the container.

### Manual Setup

If you prefer to set up manually:

1. Create the data directory and INI files for bind mounts:
   ```bash
   mkdir -p data
   touch data/SkimSrv.ini data/UberSDRIntf.ini
   ```

2. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your station details (no quotes needed for values with spaces):
   ```bash
   CALLSIGN=YOUR_CALL
   NAME=Your Name
   QTH=Your Location
   SQUARE=Your Grid Square
   UBERSDR_HOST=your_ubersdr_host
   UBERSDR_PORT=8080

   # Optional: Enable/disable specific bands
   BAND_160M=false
   BAND_80M=true
   BAND_60M=true
   # ... etc
   ```

4. Start the container:
   ```bash
   docker compose up -d
   ```

### Accessing the Interface

- Open your browser to `http://localhost:7373`
- You'll see the XFCE desktop with CW Skimmer running
- View logs: `docker compose logs -f cwskimmer`

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

## Configuration Management

All configuration is managed through environment variables in your [`.env`](.env) file. Configuration files are automatically generated at container startup based on these variables.

### Environment-Based Configuration

The startup script automatically configures:

1. **SkimSrv instances** (both 1 and 2):
   - Station information (callsign, QTH, name, grid square)
   - Band selection (which bands to monitor)
   - Center frequencies and CW segments
   - Frequency calibration
   - Telnet ports (7300 and 7301)

2. **UberSDR driver** (both instances):
   - SDR host and port
   - Calibration settings

3. **RBN Aggregator**:
   - Primary skimmer connection (port 7300)
   - Secondary skimmer connection (port 7301)
   - Station callsign

### Docker Compose Volume Configuration

```yaml
volumes:
  # Shared volume for restart trigger
  - restart-trigger:/var/run/restart-trigger
```

### Configuration at Startup

Every time the container starts, the [`startup.sh`](config/startup.sh) script:
1. Reads environment variables from your `.env` file
2. Generates fresh INI files with current settings
3. Configures both SkimSrv instances
4. Configures both UberSDR driver instances
5. Configures RBN Aggregator connections

### Benefits of Environment-Based Configuration

1. **Single Source of Truth**: All settings in one `.env` file
2. **Version Control Friendly**: Track configuration changes in git
3. **Easy Backup**: Just backup your `.env` file
4. **No Manual Editing**: No need to edit INI files directly
5. **Consistent Configuration**: Both instances always have matching settings
6. **Simple Updates**: Change `.env` and restart container

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

## Band Configuration

CW Skimmer can monitor multiple amateur radio bands simultaneously using the 192 kHz bandwidth mode. You can control which bands are active using environment variables.

### Dual Instance Architecture

**Important**: SkimSrv has an 8-band limit per instance. To support monitoring all 10 HF bands, this container runs **two SkimSrv instances**:

- **Instance 1** (port 7300): Handles the first 8 enabled bands
- **Instance 2** (port 7301): Handles bands 9-10 if enabled

Both instances run automatically:
- If you enable ≤8 bands: Instance 1 monitors them all, instance 2 runs idle
- If you enable 9-10 bands: Bands are automatically split between instances

### How It Works

The startup script automatically configures three key parameters in both [`SkimSrv.ini`](config/skimsrv/SkimSrv.ini) files:

1. **CenterFreqs192**: Fixed list of center frequencies for each band (automatically set)
2. **CwSegments**: CW portions of each band to monitor (automatically set)
3. **SegmentSel192**: Binary string controlling which bands are enabled (built from your environment variables)

### Configuring Bands

Edit your [`.env`](.env) file to enable or disable specific bands:

```bash
# Band Selection for 192 kHz Mode
BAND_160M=false  # 160m often has high noise
BAND_80M=true
BAND_60M=true
BAND_40M=true
BAND_30M=true
BAND_20M=true
BAND_17M=true
BAND_15M=true
BAND_12M=true
BAND_10M=true
```

### Band Details

| Band | Center Freq | CW Segment | Typical Use |
|------|-------------|------------|-------------|
| 160m | 1.891 MHz | 1.800-1.840 MHz | Long distance, high noise |
| 80m | 3.591 MHz | 3.500-3.570 MHz | Regional/DX, day/night |
| 60m | 5.355 MHz | 5.258-5.370 MHz | Regional, limited allocation |
| 40m | 7.091 MHz | 7.000-7.070 MHz | Workhorse DX band |
| 30m | 10.191 MHz | 10.100-10.130 MHz | WARC band, CW only |
| 20m | 14.091 MHz | 14.000-14.070 MHz | Premier DX band |
| 17m | 18.159 MHz | 18.068-18.095 MHz | WARC band |
| 15m | 21.091 MHz | 21.000-21.070 MHz | DX when open |
| 12m | 24.981 MHz | 24.890-24.920 MHz | WARC band |
| 10m | 28.091 MHz | 28.000-28.070 MHz | DX during solar max |

### Technical Details

The `SegmentSel192` parameter is a 10-character binary string where each position corresponds to a band:

```
Position: 0123456789
Bands:    160 80 60 40 30 20 17 15 12 10
Example:  0111111111  (all bands except 160m)
```

The startup script automatically builds this string based on your `BAND_*` environment variables, so you don't need to manually calculate the binary values.

### Why Disable Bands?

You might want to disable certain bands for several reasons:

- **Noise**: 160m often has high atmospheric/man-made noise
- **Propagation**: Some bands may be dead at certain times
- **Focus**: Concentrate on specific bands for contests or DXing
- **Performance**: Reduce CPU load by monitoring fewer bands
- **Licensing**: Some bands may have restrictions in your jurisdiction

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
