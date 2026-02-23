#!/bin/bash
# CW Skimmer entrypoint wrapper with restart trigger support
# Based on caddy-entrypoint.sh from ka9q_ubersdr

# Default CWSKIMM_ENABLED to true if not set
: ${CWSKIMM_ENABLED:=true}

# Create restart trigger directory
mkdir -p /var/run/restart-trigger

# Start background watcher for restart trigger file
# When trigger file is detected, kill PID 1 (supervisord) to trigger container restart
(
    while true; do
        if [ -f /var/run/restart-trigger/restart-cwskimmer ]; then
            echo "Restart trigger detected at $(date), killing PID 1 to restart container..."
            rm -f /var/run/restart-trigger/restart-cwskimmer
            # Try graceful shutdown first, then force kill if needed
            kill -TERM 1 || kill -9 1 || echo "Warning: Failed to kill PID 1"
            # Don't exit - let the loop continue in case restart is needed again
            sleep 1
        fi
        sleep 0.5
    done
) &

# Check if CW Skimmer should be enabled
if [ "$CWSKIMM_ENABLED" = "true" ] || [ "$CWSKIMM_ENABLED" = "1" ]; then
    echo "CWSKIMM_ENABLED is true, starting CW Skimmer services..."
    # Execute the original startup.sh script
    exec /bin/startup.sh "$@"
else
    echo "CWSKIMM_ENABLED is false, keeping container alive without starting services..."
    echo "Restart trigger watcher is still active. Set CWSKIMM_ENABLED=true and trigger restart to enable services."
    # Keep container alive with a sleep loop
    while true; do
        sleep 3600
    done
fi
