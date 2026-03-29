#!/bin/bash
# Restart CW Skimmer container

set -e

echo "Restarting CW Skimmer container..."
docker compose down

echo ""
echo "Starting CW Skimmer container..."
docker compose up -d

echo ""
echo "✓ Container restarted successfully!"
echo ""
echo "Access the web interface at: http://ubersdr.local:7373/vnc.html?autoconnect=true"
echo "View logs with: docker compose logs -f cwskimmer"
echo ""
