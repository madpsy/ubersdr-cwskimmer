# Docker CW Skimmer

This project is based on the original work by [8cH9azbsFifZ](https://github.com/8cH9azbsFifZ/docker-cwskimmer).

## Quick Start (recommended — no repo clone needed)

> **Run this on your UberSDR machine** (the Linux host running ka9q-radio / ka9q_ubersdr).

Run the one-line installer. It pulls the pre-built image from Docker Hub, downloads only the files it needs, walks you through station configuration, and starts the container:

```bash
curl -fsSL https://raw.githubusercontent.com/madpsy/ubersdr-cwskimmer/main/install-hub.sh | bash
```

The installer will:
1. Check that Docker and Docker Compose are installed
2. Pull `madpsy/ubersdr-cwskimmer:latest` from Docker Hub
3. Download `docker-compose.yml` and `.env.example` into `~/ubersdr/cwskimmer/`
4. Prompt you for your callsign, QTH, grid square, UberSDR host/port, and band selection
5. Write a ready-to-use `.env` file
6. Check for (or offer to create) the `ubersdr_sdr-network` Docker network
7. Start the container

Files are installed into `~/ubersdr/cwskimmer/` (created automatically if it doesn't exist).

### Updating

Use the dedicated update script — it pulls the latest image, refreshes `docker-compose.yml`, and restarts the container without touching your `.env`:

```bash
bash ~/ubersdr/cwskimmer/update.sh
```

Or re-run the full installer (same effect on an existing install):

```bash
bash ~/ubersdr/cwskimmer/install-hub.sh
```

### After installation

Connect to the VNC web interface at:

**Direct access** (port 7373 exposed on the host):
```
http://ubersdr.local:7373/vnc.html?autoconnect=true
```

**Via the ka9q_ubersdr addon proxy** (e.g. behind the UberSDR web interface):
```
http://ubersdr.local:8080/addon/cwskimmer/vnc.html?autoconnect=true&path=addon/cwskimmer/websockify
```
The `path` parameter tells noVNC to connect its WebSocket to the correct proxy sub-path instead of the bare `/websockify` endpoint.

Configure ka9q_ubersdr to connect to the Aggregator on port 7550:
   - The Aggregator provides a telnet interface on port 7550
   - Configure your ka9q_ubersdr instance to connect to `cwskimmer:7550` (or `ubersdr.local:7550` from outside the Docker network)
   - This allows ka9q_ubersdr to receive CW spots from the skimmer

---

## Developer Quick Start (from source)

1. Clone the repository:
```bash
git clone https://github.com/madpsy/ubersdr-cwskimmer.git
cd ubersdr-cwskimmer
```

2. Run the start script:
```bash
./start.sh
```

3. The script will error and prompt you to configure your station. Edit the `.env` file and set your station information:
```bash
nano .env
```

4. Run the start script again:
```bash
./start.sh
```

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

### RBN Aggregator Window Size

| Variable | Default | Description |
|----------|---------|-------------|
| `AGGREGATOR_WIDTH` | `1144` | Aggregator window width (pixels) |
| `AGGREGATOR_HEIGHT` | `722` | Aggregator window height (pixels) |

The Aggregator window is resized to `AGGREGATOR_WIDTH`x`AGGREGATOR_HEIGHT` once, immediately after it appears. This happens on initial container startup **and** any time the Aggregator process itself is restarted by supervisor (e.g. after a crash), so the window is always correctly sized regardless of how many times Aggregator has restarted. Because the resize only happens right after launch (not on a repeating timer), you're free to manually resize the window afterwards via the VNC session — it will stay however you leave it until the next actual Aggregator restart.

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
| `BAND_10M_BEACONS` | `true` | 28.225 MHz | 10m | Beacon segment (28.200-28.300 MHz) |
| `BAND_6M` | `false` | 50.091 MHz | 6m | CW allocation, 50.000-50.100 MHz — requires a receiver that tunes above 50 MHz |
| `BAND_6M_BEACONS` | `false` | 50.491 MHz | 6m | IARU **Region 1** beacon band, 50.400-50.500 MHz |

**Note**: The center frequencies and CW segments are automatically configured. These settings only control which bands are enabled/disabled.

#### NCDXF beacon segments (96 kHz mode)

| Variable | Default | Center Freq | Description |
|----------|---------|-------------|-------------|
| `BAND_20M_BEACONS` | `false` | 14.100 MHz | 20m NCDXF beacon slot |
| `BAND_15M_BEACONS` | `false` | 21.150 MHz | 15m NCDXF beacon slot |

A 96 kHz channel is only 91 kHz wide, so the 20m and 15m channels stop at 14.091 and 21.091 and cannot reach the NCDXF beacon frequencies. These two settings add a channel each that does reach them, independently of `BAND_20M` / `BAND_15M`, at the cost of one of the eight SkimSrv slots per instance.

> **Known issue:** SkimSrv allocates **no decoders** to these two channels, so they occupy a slot and produce no spots. Every other channel has a `CwSegments` entry of its own; the nearest entries to 14.100 and 21.150 (`14.000-14.105` and `21.000-21.155`) sit almost entirely under the main 20m/15m channels. Splitting those entries to give the beacon channels their own took `CwSegments` from 14 entries to 16, at which point SkimSrv spun up zero decoders on nearly every band — so the list has to stay at 14 and this is unfixed. Leave both `false` unless you are testing.

At 192 kHz the 182 kHz-wide 20m and 15m channels already cover 14.100 and 21.150, so `SegmentSel192` has no entry for them and both settings are ignored.

#### Center frequency vs. displayed dial frequency

The `CenterFreqs*` values above are **not** what SkimSrv shows on screen. SkimSrv uses only part of each sampled window — 91 kHz of the 96, and 182 kHz of the 192, the rest being guard band — and it displays the **bottom edge of that usable passband** as the dial frequency.

So every entry is written as `segment start + 45500` (96 kHz mode) or `segment start + 91000` (192 kHz mode), which makes each band read as a round number:

| Band | 96 kHz centre | 192 kHz centre | Displayed as |
|------|---------------|----------------|--------------|
| 40m | 7.0455 MHz | 7.091 MHz | `7.000.0` |
| 10m | 28.0455 MHz | 28.091 MHz | `28.000.0` |
| 6m | 50.0545 MHz | 50.091 MHz | `50.009.0` / `50.000.0` |
| 6m beacons | 50.4455 MHz | 50.491 MHz | `50.400.0` |

6m is the one band where the two modes differ. At 192 kHz the 182 kHz passband swallows the whole 100 kHz CW allocation, so the centre follows the usual pattern and reads `50.000.0`. At 96 kHz only 91 kHz is usable, so 9 kHz of the allocation has to be given up — the bottom 9 kHz (50.000-50.009) is dropped as dead band-edge space, keeping the 50.060-50.080 Region 2 beacon sub-band and the 50.090 CW DX calling frequency comfortably inside the passband instead of against its roll-off. That is why 6m reads `50.009.0` rather than `50.000.0` in 96 kHz mode.

#### 6m and the receiver's tuning range

Many UberSDR instances stop at 30 MHz, so 6m is opt-in and defaults to `false`.

On every container start the skimmer reads `tuning_range.max_frequency` from the UberSDR API (`/api/description`) and disables any band whose IQ window falls outside what the receiver can tune — the test is *centre frequency ± sample rate / 2* against the reported `min_frequency`/`max_frequency`. A 6m band left enabled on a 30 MHz instance is therefore switched off with a log line rather than tying up one of the eight SkimSrv slots with a segment that can never produce a spot:

```
UberSDR tuning range: 10000 - 30000000 Hz
  6M: disabled — needs 49995000-50187000 Hz, receiver covers 10000-30000000 Hz
1 band(s) disabled as out of range for this receiver
```

If the API cannot be reached the check is skipped and your configured bands are left as-is, with a warning in the log.

`install-hub.sh` uses the same field to pick the initial default, enabling `BAND_6M` on a fresh install when the receiver reaches 50 MHz. `update.sh` seeds the two keys into an existing `.env` if they are missing, but never overrides a choice you have already made.

`BAND_6M_BEACONS` covers the IARU Region 1 beacon band at 50.400-50.500 MHz and stays `false` by default — outside Region 1 (Europe/Africa/Middle East) it has nothing to hear. Region 2's beacon sub-band at 50.060-50.080 MHz sits inside the CW allocation and is already covered by `BAND_6M`.

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
BAND_10M_BEACONS=true
BAND_20M_BEACONS=false  # 14.100 MHz NCDXF beacons, 96 kHz only — see known issue
BAND_15M_BEACONS=false  # 21.150 MHz NCDXF beacons, 96 kHz only — see known issue
BAND_6M=false           # 50 MHz — needs a receiver that tunes above 30 MHz
BAND_6M_BEACONS=false   # 50.400-50.500 MHz, IARU Region 1 only
```

### Band Details

| Band | Center Freq | CW Segment | Typical Use |
|------|-------------|------------|-------------|
| 160m | 1.891 MHz | 1.800-1.840 MHz | Long distance, high noise |
| 80m | 3.591 MHz | 3.500-3.570 MHz | Regional/DX, day/night |
| 60m | 5.355 MHz | 5.258-5.370 MHz | Regional, limited allocation |
| 40m | 7.091 MHz | 7.000-7.070 MHz | Workhorse DX band |
| 30m | 10.191 MHz | 10.100-10.130 MHz | WARC band, CW only |
| 20m | 14.091 MHz | 14.000-14.105 MHz | Premier DX band |
| 17m | 18.159 MHz | 18.068-18.095 MHz | WARC band |
| 15m | 21.091 MHz | 21.000-21.155 MHz | DX when open |
| 12m | 24.981 MHz | 24.890-24.920 MHz | WARC band |
| 10m | 28.091 MHz | 28.000-28.070 MHz | DX during solar max |
| 10m beacons | 28.225 MHz | 28.200-28.300 MHz | NCDXF and other beacons |
| 6m | 50.091 MHz | 50.000-50.100 MHz | Sporadic-E and solar max openings |
| 6m beacons | 50.491 MHz | 50.400-50.500 MHz | IARU Region 1 beacon band |
| 20m beacons | 14.100 MHz | (no segment of its own) | NCDXF beacons, 96 kHz mode only |
| 15m beacons | 21.150 MHz | (no segment of its own) | NCDXF beacons, 96 kHz mode only |

### Technical Details

The `SegmentSel192` parameter is a 13-character binary string where each position corresponds to an entry in `CenterFreqs192`:

```
Position: 0  1  2  3  4  5  6  7  8  9  10       11 12
Bands:    160 80 60 40 30 20 17 15 12 10 10m-bcn 6m 6m-bcn
Example:  0111111111100  (all HF bands except 160m, no 6m)
```

In 96 kHz mode the equivalent `SegmentSel96` is 16 characters, because that mode carries extra centre frequencies for the 20m and 15m NCDXF beacon segments (positions 14 and 15, driven by `BAND_20M_BEACONS` and `BAND_15M_BEACONS`).

The startup script automatically builds this string based on your `BAND_*` environment variables, so you don't need to manually calculate the binary values.

SkimSrv accepts at most 8 segments per instance, and the container runs two instances (ports 7300 and 7301) — so up to 16 bands total. The first 8 enabled bands go to instance 1 and the remainder to instance 2. If you enable more than 16, the excess is listed as a warning in the startup log rather than being silently dropped.

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
