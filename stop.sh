#!/bin/bash
# Stop CW Skimmer container

set -e

# Always run from the directory containing this script
cd "$(dirname "$(realpath "$0")")"

echo "Stopping CW Skimmer container..."
docker compose down

echo ""
echo "✓ Container stopped successfully!"
echo ""
echo "To start again, run: ./start.sh"
echo ""
