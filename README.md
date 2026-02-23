# SkimSrv Persistent Volumes

## Overview

Two persistent Docker volumes have been configured for SkimSrv that can be shared between containers:

1. **skimsrv** - SkimSrv application directory (contains `UberSDRIntf.ini`)
2. **skimsrv_config** - SkimSrv configuration directory (contains `SkimSrv.ini`)

## Configuration Details

### Volume 1: skimsrv
- **Container Path**: `/skimmersrv_1.6/app/`
- **Volume Name**: `skimsrv`
- **Contains**: `UberSDRIntf.ini` and application files

### Volume 2: skimsrv_config
- **Container Path**: `/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/`
- **Volume Name**: `skimsrv_config`
- **Contains**: `SkimSrv.ini` and user configuration

### Docker Compose Configuration

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

## Benefits

1. **Persistence**: Configuration survives container restarts and removals
2. **Shareability**: Other containers can mount the same volume to access the configuration
3. **Backup**: Easy to backup and restore using Docker volume commands

## Usage

### Sharing with Other Containers

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

## Configuration Parameters

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

## Notes

- Both volumes are created automatically when you first run `docker-compose up`
- Configurations are modified at startup based on environment variables
- Entire directories are persisted, not just the INI files
- This ensures all related application and configuration files are preserved across container restarts
