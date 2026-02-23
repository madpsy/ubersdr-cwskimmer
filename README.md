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

## Configuration Files

The container includes pre-configured templates for:
- **SkimSrv.ini** - Skimmer Server configuration
- **Aggregator.ini** - RBN Aggregator configuration
- **UberSDRIntf.ini** - UberSDR driver settings

These files are automatically updated at startup with your environment variables.

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

## License

Please refer to the original repository for licensing information.

## Credits

- Original Docker implementation: [8cH9azbsFifZ/docker-cwskimmer](https://github.com/8cH9azbsFifZ/docker-cwskimmer)
- CW Skimmer: Afreet Software
- RBN Aggregator: Reverse Beacon Network
- ka9q_ubersdr driver: [madpsy/ka9q_ubersdr](https://github.com/madpsy/ka9q_ubersdr)
