#!/bin/bash
# Stop CW Skimmer container

set -e

echo "Stopping CW Skimmer container..."
docker compose down

echo ""
echo "✓ Container stopped successfully!"
echo ""
echo "To start again, run: ./start.sh"
echo ""
