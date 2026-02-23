#!/bin/bash
# Start CW Skimmer container
# This script ensures data directory exists and starts the container

set -e

# Ensure data directory and INI files exist for bind mounts
echo "Setting up data directory..."
mkdir -p data
touch data/SkimSrv.ini
touch data/UberSDRIntf.ini

# Check if .env file exists, if not copy from example
if [ ! -f .env ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo ""
    echo "⚠️  Please edit .env file with your configuration:"
    echo "   - CALLSIGN: Your amateur radio callsign"
    echo "   - NAME: Your name"
    echo "   - QTH: Your location (no quotes needed)"
    echo "   - SQUARE: Your Maidenhead grid square"
    echo "   - UBERSDR_HOST: Your ka9q_ubersdr server hostname/IP"
    echo ""
    echo "After editing .env, run this script again to start the container."
    exit 0
fi

# Start the container
echo "Starting CW Skimmer container..."
docker compose up -d

echo ""
echo "✓ Container started successfully!"
echo ""
echo "Access the web interface at: http://localhost:7373"
echo "View logs with: docker compose logs -f cwskimmer"
echo ""
