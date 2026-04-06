#!/bin/bash
# Restart CW Skimmer container

set -e

# Always run from the directory containing this script
cd "$(dirname "$(realpath "$0")")"

echo "Restarting CW Skimmer container..."
docker compose down

echo ""
echo "Starting CW Skimmer container..."
docker compose up -d

echo ""
echo "✓ Container restarted successfully!"
echo ""
echo "Access the web interface at (direct):     http://ubersdr.local:7373/vnc.html?autoconnect=true"
echo "Access the web interface at (via proxy):  http://ubersdr.local:8080/addon/cwskimmer/vnc.html?autoconnect=true&path=addon/cwskimmer/websockify"
echo "View logs with: docker compose logs -f cwskimmer"
echo ""
