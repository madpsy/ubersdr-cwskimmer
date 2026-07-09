#!/bin/bash
# Wrapper around RBN Aggregator's Wine process.
#
# Supervisor runs this script (instead of calling wine directly) as the
# [program:rbnaggregator] command. Every time supervisor (re)starts this
# program - whether on initial container boot or after Aggregator has
# crashed - this script relaunches Wine and waits for the Aggregator
# window to appear, then resizes it exactly once.
#
# This fixes the previous design where a separate one-shot
# "aggregator-resize" supervisor program only ever resized the window the
# very first time it appeared, then permanently exited (exitcodes=0 /
# autorestart=unexpected), leaving any window opened by a post-crash
# restart at its default (unresized) size.
#
# Because the resize only happens once right after (re)launch - not on a
# repeating timer - any manual resize the user performs afterwards (e.g.
# via the noVNC session) is left alone until the next actual restart.

set -u

: "${V_RBNAGGREGATOR:=6.7}"
: "${AGGREGATOR_WIDTH:=1144}"
: "${AGGREGATOR_HEIGHT:=722}"
: "${DISPLAY:=:0}"

AGGREGATOR_EXE="/rbnaggregator_${V_RBNAGGREGATOR}/Aggregator v${V_RBNAGGREGATOR}.exe"

echo "run-aggregator: launching ${AGGREGATOR_EXE}"
/usr/bin/wine "${AGGREGATOR_EXE}" &
WINE_PID=$!

echo "run-aggregator: waiting for Aggregator window to resize to ${AGGREGATOR_WIDTH}x${AGGREGATOR_HEIGHT}..."
RESIZED=false
for _ in $(seq 1 60); do
    # Stop waiting if Wine already exited (e.g. crashed before showing a window)
    if ! kill -0 "$WINE_PID" 2>/dev/null; then
        echo "run-aggregator: wine process exited before window appeared"
        break
    fi

    if DISPLAY="${DISPLAY}" xdotool search --name "Aggregator" windowsize "${AGGREGATOR_WIDTH}" "${AGGREGATOR_HEIGHT}" >/dev/null 2>&1; then
        echo "run-aggregator: window resized to ${AGGREGATOR_WIDTH}x${AGGREGATOR_HEIGHT}"
        RESIZED=true
        break
    fi

    sleep 1
done

if [ "$RESIZED" = "false" ] && kill -0 "$WINE_PID" 2>/dev/null; then
    echo "run-aggregator: window not found after 60s, giving up on resize (Aggregator keeps running)"
fi

# Keep supervisor's process tracking accurate: this script's exit code
# mirrors Wine's own exit code, so autorestart=true behaves exactly as it
# did when supervisor called wine directly.
wait "$WINE_PID"
exit $?
